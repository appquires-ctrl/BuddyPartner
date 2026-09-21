import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/app_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/core/config/app_config.dart';
import 'package:buddypartner/core/utils/app_logger.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';

import 'package:buddypartner/features/auth/application/auth_state_provider.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(ref));

class ApiClient {
  late final Dio dio;
  final Ref? _ref;
  final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
  );
  static const _tokenKey = 'auth_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _userSessionKey = 'cached_user_session';
  static String? _cachedAppVersion;
  static String? _cachedToken;
  static String? _cachedRefreshToken;
  bool _isRefreshing = false;

  /// Checks whether a DioException represents a client-side offline or DNS resolution failure.
  /// When true, retrying is counter-productive because the client has no network connectivity.
  static bool isOfflineOrDnsError(DioException err) {
    if (err.type == DioExceptionType.connectionError) {
      final error = err.error;
      if (error is SocketException) {
        final msg = error.message.toLowerCase();
        final osMsg = (error.osError?.message ?? '').toLowerCase();
        final osCode = error.osError?.errorCode ?? 0;
        if (msg.contains('failed host lookup') ||
            msg.contains('no address associated') ||
            msg.contains('network is unreachable') ||
            msg.contains('connection refused') ||
            osMsg.contains('no address associated') ||
            osMsg.contains('network unreachable') ||
            osCode == 7 ||
            osCode == 101 ||
            osCode == 111 ||
            osCode == 113 ||
            osCode == 11001 ||
            osCode == 10051 ||
            osCode == 10061) {
          return true;
        }
      }
      final errMessage = (err.message ?? '').toLowerCase();
      if (errMessage.contains('failed host lookup') ||
          errMessage.contains('no address associated') ||
          errMessage.contains('network is unreachable')) {
        return true;
      }
    }
    return false;
  }

  /// Cache app version once at startup to prevent native platform-channel delays on every API call.
  static Future<void> initAppVersion() async {
    try {
      if (kIsWeb) {
        _cachedAppVersion = '1.0.0';
      } else {
        final pkg = await PackageInfo.fromPlatform();
        _cachedAppVersion = pkg.version;
      }
    } catch (_) {
      _cachedAppVersion = 'unknown';
    }
  }

  static String get appVersion => _cachedAppVersion ?? 'unknown';

  ApiClient([this._ref]) {
    dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.backendUrl,
        // Production 5,000 CCU mobile timeouts:
        // 8s connect timeout ensures instant fast-fail when offline or DNS unresolvable,
        // and prevents socket descriptor exhaustion on the reverse proxy.
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // Interceptor to automatically attach custom JWT session token, handle 401 silent refresh & 403 ban
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          AppLogger.apiStart(options.method, options.path);
          final token = await getToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }

          // Attach version & platform headers synchronously from cached values
          try {
            final platform = kIsWeb ? 'android' : (Platform.isIOS ? 'ios' : 'android');
            options.headers['X-App-Platform'] = platform;
            options.headers['X-App-Version'] = _cachedAppVersion ?? 'unknown';
          } catch (_) {}

          return handler.next(options);
        },
        onResponse: (response, handler) {
          AppLogger.apiSuccess(
            response.requestOptions.method,
            response.requestOptions.path,
            response.statusCode ?? 200,
          );
          return handler.next(response);
        },
        onError: (DioException err, handler) async {
          final isOffline = isOfflineOrDnsError(err);

          // Do not log routine client-side request cancellations as API failures
          if (err.type != DioExceptionType.cancel) {
            if (isOffline) {
              // Clean log for offline/DNS failure: prevents 15 startup requests from flooding logs with multi-line errors
              debugPrint('ℹ️ [Offline] ${err.requestOptions.method} ${err.requestOptions.path}: No internet or DNS unreachable');
            } else {
              AppLogger.apiError(
                err.requestOptions.method,
                err.requestOptions.path,
                err.response?.statusCode,
                err.error ?? err.message ?? 'Network Error',
              );
            }
          }

          // Handle HTTP 426 Upgrade Required
          if (err.response?.statusCode == 426) {
            final context = rootNavigatorKey.currentContext;
            if (context != null) {
              context.go(RouteNames.updateRequired);
            }
          }

          // Production 5,000 CCU Reliability Rules:
          // 1. NEVER auto-retry if device is offline or host DNS lookup failed (guaranteed to fail, freezes UI, drains battery).
          // 2. ONLY retry idempotent methods (GET, HEAD, OPTIONS). Retrying mutating POST/PATCH/DELETE could cause duplicate coin debits or duplicate operations.
          // 3. NEVER auto-retry non-idempotent OTP or financial endpoints.
          final method = err.requestOptions.method.toUpperCase();
          final isIdempotent = method == 'GET' || method == 'HEAD' || method == 'OPTIONS';
          final isOtpEndpoint = err.requestOptions.path.contains('/otp/');

          final isTimeoutOrConnErr = err.type == DioExceptionType.connectionTimeout ||
              err.type == DioExceptionType.receiveTimeout ||
              err.type == DioExceptionType.sendTimeout ||
              (err.type == DioExceptionType.connectionError && !isOffline);

          final retried = err.requestOptions.extra['retried'] == true;
          if (!isOffline && isIdempotent && isTimeoutOrConnErr && !retried && !isOtpEndpoint) {
            err.requestOptions.extra['retried'] = true;
            try {
              // Full Jitter Backoff (1.5s - 3.0s):
              // Prevents a Thundering Herd from 5,000 CCU hitting Render at the exact same millisecond.
              final jitterMs = 1500 + Random().nextInt(1500);
              AppLogger.apiError(
                err.requestOptions.method,
                err.requestOptions.path,
                null,
                'Transient timeout. Retrying request after ${(jitterMs / 1000).toStringAsFixed(1)}s (jittered)...',
              );
              await Future.delayed(Duration(milliseconds: jitterMs));
              final cloneReq = await dio.fetch(err.requestOptions);
              return handler.resolve(cloneReq);
            } catch (_) {
              // If retry fails, fall through to normal error handling
            }
          }

          // Handle 401 Session Terminated (Single device login policy) FIRST before silent refresh
          if (err.response?.statusCode == 401) {
            final data = err.response?.data;
            if (data is Map<String, dynamic> && data['error'] == 'SESSION_TERMINATED') {
              await clearTokens();
              if (_ref != null) {
                try {
                  await _ref.read(authStateProvider.notifier).clearSession();
                } catch (_) {}
              }
              final context = rootNavigatorKey.currentContext;
              if (context != null && context.mounted) {
                AppSnackBar.showError(
                  context,
                  data['message']?.toString() ?? 'Your account was logged in from another device. Please log in again.',
                );
                context.go(RouteNames.login);
              }
              return handler.next(err);
            }
          }

          // Handle 401 Unauthorized with silent token refresh attempt (only if not SESSION_TERMINATED)
          if (err.response?.statusCode == 401 && 
              !err.requestOptions.path.contains('/api/auth/otp/verify') &&
              !err.requestOptions.path.contains('/api/auth/refresh')) {
            final curRefreshToken = await getRefreshToken();
            if (curRefreshToken == null || curRefreshToken.isEmpty) {
              return handler.next(err);
            }

            if (!_isRefreshing) {
              _isRefreshing = true;
              try {
                final refreshed = await refreshToken();
                _isRefreshing = false;
                if (refreshed) {
                  // Retry original failed request with new access token
                  final newToken = await getToken();
                  final opts = err.requestOptions;
                  opts.headers['Authorization'] = 'Bearer $newToken';
                  final cloneReq = await dio.fetch(opts);
                  return handler.resolve(cloneReq);
                } else {
                  // Refresh token was invalid or rejected by server: clear tokens and session
                  await clearTokens();
                  if (_ref != null) {
                    try {
                      await _ref.read(authStateProvider.notifier).clearSession();
                    } catch (_) {}
                  }
                }
              } catch (_) {
                _isRefreshing = false;
              }
            }
          }

          // Handle 403 Account Ban/Suspension redirect
          if (err.response?.statusCode == 403) {
            final data = err.response?.data;
            if (data is Map<String, dynamic>) {
              final errorCode = data['error'];
              final context = rootNavigatorKey.currentContext;
              if (context != null && context.mounted) {
                if (errorCode == 'ACCOUNT_BANNED' || errorCode == 'ACCOUNT_SUSPENDED') {
                  context.go(RouteNames.banned);
                }
              }
            }
          }
          return handler.next(err);
        },
      ),
    );
  }

  /// Write access and refresh tokens to platform secure storage and in-memory cache
  Future<void> saveTokens({required String token, required String refreshToken}) async {
    _cachedToken = token;
    _cachedRefreshToken = refreshToken;
    try {
      await _secureStorage.write(key: _tokenKey, value: token);
      await _secureStorage.write(key: _refreshTokenKey, value: refreshToken);
    } catch (_) {}
  }

  /// Write access JWT token to platform secure storage and in-memory cache
  Future<void> saveToken(String token) async {
    _cachedToken = token;
    try {
      await _secureStorage.write(key: _tokenKey, value: token);
    } catch (_) {}
  }

  /// Read Access JWT token from in-memory cache first, falling back to secure storage
  Future<String?> getToken() async {
    if (_cachedToken != null && _cachedToken!.isNotEmpty) {
      return _cachedToken;
    }
    try {
      final token = await _secureStorage.read(key: _tokenKey);
      _cachedToken = token;
      return token;
    } catch (e) {
      try {
        await _secureStorage.deleteAll();
      } catch (_) {}
      _cachedToken = null;
      return null;
    }
  }

  /// Read Refresh token from in-memory cache first, falling back to secure storage
  Future<String?> getRefreshToken() async {
    if (_cachedRefreshToken != null && _cachedRefreshToken!.isNotEmpty) {
      return _cachedRefreshToken;
    }
    try {
      final token = await _secureStorage.read(key: _refreshTokenKey);
      _cachedRefreshToken = token;
      return token;
    } catch (e) {
      try {
        await _secureStorage.deleteAll();
      } catch (_) {}
      _cachedRefreshToken = null;
      return null;
    }
  }

  /// Save serialized user session to platform secure storage
  Future<void> saveUserSessionJson(Map<String, dynamic> userMap) async {
    try {
      await _secureStorage.write(key: _userSessionKey, value: jsonEncode(userMap));
    } catch (_) {}
  }

  /// Read serialized user session from platform secure storage
  Future<Map<String, dynamic>?> getUserSessionJson() async {
    try {
      final jsonStr = await _secureStorage.read(key: _userSessionKey);
      if (jsonStr == null || jsonStr.trim().isEmpty) return null;
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Delete cached user session
  Future<void> deleteUserSessionJson() async {
    try {
      await _secureStorage.delete(key: _userSessionKey);
    } catch (_) {}
  }

  /// Delete both tokens & user session from platform secure storage and clear in-memory cache (logout)
  Future<void> deleteTokens() async {
    _cachedToken = null;
    _cachedRefreshToken = null;
    try {
      await _secureStorage.delete(key: _tokenKey);
      await _secureStorage.delete(key: _refreshTokenKey);
      await deleteUserSessionJson();
    } catch (_) {
      try {
        await _secureStorage.deleteAll();
      } catch (_) {}
    }
  }

  /// Alias for deleteTokens
  Future<void> deleteToken() async {
    await deleteTokens();
  }

  /// Alias for deleteTokens
  Future<void> clearTokens() async {
    await deleteTokens();
  }

  /// Check if a valid JWT access token exists locally
  Future<bool> hasToken() async {
    final token = await getToken();
    return token != null && token.trim().isNotEmpty;
  }

  /// Attempt silent token refresh via POST /api/auth/refresh
  Future<bool> refreshToken() async {
    final curRefreshToken = await getRefreshToken();
    if (curRefreshToken == null || curRefreshToken.isEmpty) return false;

    try {
      final response = await dio.post(
        '/api/auth/refresh',
        data: {'refreshToken': curRefreshToken},
      );

      if (response.statusCode == 200 && response.data != null) {
        final newToken = response.data['token'] as String;
        final newRefreshToken = response.data['refreshToken'] as String;
        await saveTokens(token: newToken, refreshToken: newRefreshToken);
        return true;
      }
    } on DioException catch (e) {
      // Only delete tokens if server explicitly returned 401 or 403 (invalid/revoked refresh token)
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        await deleteTokens();
      }
    } catch (e) {
      // Network timeout / offline error — preserve local tokens for offline/retry
    }
    return false;
  }

  static const _hasSeenOnboardingKey = 'has_seen_onboarding';

  /// Check if user has already seen the 3-screen onboarding intro
  Future<bool> hasSeenOnboarding() async {
    try {
      final value = await _secureStorage.read(key: _hasSeenOnboardingKey);
      return value == 'true';
    } catch (_) {
      return false;
    }
  }

  /// Mark onboarding as completed so it is never shown again
  Future<void> setSeenOnboarding() async {
    try {
      await _secureStorage.write(key: _hasSeenOnboardingKey, value: 'true');
    } catch (_) {}
  }
}

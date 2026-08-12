import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:dating_app/app/router/app_router.dart';
import 'package:dating_app/app/router/route_names.dart';
import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/utils/app_logger.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

class ApiClient {
  late final Dio dio;
  final _secureStorage = const FlutterSecureStorage();
  static const _tokenKey = 'auth_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _userSessionKey = 'cached_user_session';
  bool _isRefreshing = false;

  ApiClient() {
    dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.backendUrl,
        connectTimeout: const Duration(seconds: 35),
        receiveTimeout: const Duration(seconds: 35),
        sendTimeout: const Duration(seconds: 35),
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
          AppLogger.apiError(
            err.requestOptions.method,
            err.requestOptions.path,
            err.response?.statusCode,
            err.error ?? err.message ?? 'Network Error',
          );

          // Automatic single-retry for transient network timeout / connection errors (e.g. Render server cold start)
          final isTimeoutOrConnErr = err.type == DioExceptionType.connectionTimeout ||
              err.type == DioExceptionType.receiveTimeout ||
              err.type == DioExceptionType.sendTimeout ||
              err.type == DioExceptionType.connectionError;

          final retried = err.requestOptions.extra['retried'] == true;
          if (isTimeoutOrConnErr && !retried) {
            err.requestOptions.extra['retried'] = true;
            try {
              AppLogger.apiError(
                err.requestOptions.method,
                err.requestOptions.path,
                null,
                'Connection timeout. Retrying request after 2s...',
              );
              await Future.delayed(const Duration(seconds: 2));
              final cloneReq = await dio.fetch(err.requestOptions);
              return handler.resolve(cloneReq);
            } catch (_) {
              // If retry fails, fall through to normal error handling
            }
          }

          // Handle 401 Unauthorized with silent token refresh attempt
          if (err.response?.statusCode == 401 && 
              !err.requestOptions.path.contains('/api/auth/otp/verify') &&
              !err.requestOptions.path.contains('/api/auth/refresh')) {
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
              if (context != null) {
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

  /// Write access and refresh tokens to platform secure storage
  Future<void> saveTokens({required String token, required String refreshToken}) async {
    await _secureStorage.write(key: _tokenKey, value: token);
    await _secureStorage.write(key: _refreshTokenKey, value: refreshToken);
  }

  /// Write access JWT token to platform secure storage
  Future<void> saveToken(String token) async {
    await _secureStorage.write(key: _tokenKey, value: token);
  }

  /// Read Access JWT token from platform secure storage
  Future<String?> getToken() async {
    return await _secureStorage.read(key: _tokenKey);
  }

  /// Read Refresh token from platform secure storage
  Future<String?> getRefreshToken() async {
    return await _secureStorage.read(key: _refreshTokenKey);
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

  /// Delete both tokens & user session from platform secure storage (logout)
  Future<void> deleteTokens() async {
    await _secureStorage.delete(key: _tokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
    await deleteUserSessionJson();
  }

  /// Alias for deleteTokens
  Future<void> deleteToken() async {
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
}

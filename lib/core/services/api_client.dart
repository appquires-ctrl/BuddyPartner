import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:dating_app/app/router/app_router.dart';
import 'package:dating_app/app/router/route_names.dart';
import 'package:dating_app/core/config/app_config.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

class ApiClient {
  late final Dio dio;
  final _secureStorage = const FlutterSecureStorage();
  static const _tokenKey = 'auth_token';

  ApiClient() {
    dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.backendUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // Interceptor to automatically attach custom JWT session token and handle 403 suspension/ban
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await getToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException err, handler) {
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

  /// Write JWT token to platform secure storage
  Future<void> saveToken(String token) async {
    await _secureStorage.write(key: _tokenKey, value: token);
  }

  /// Read JWT token from platform secure storage
  Future<String?> getToken() async {
    return await _secureStorage.read(key: _tokenKey);
  }

  /// Delete JWT token from platform secure storage (logout)
  Future<void> deleteToken() async {
    await _secureStorage.delete(key: _tokenKey);
  }

  /// Check if a valid JWT token exists locally
  Future<bool> hasToken() async {
    final token = await getToken();
    return token != null && token.trim().isNotEmpty;
  }
}

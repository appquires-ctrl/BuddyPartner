import 'package:dio/dio.dart';

/// AuthErrorMapper handles converting technical DioException errors and general auth errors
/// into user-friendly, localized error messages.
class AuthErrorMapper {
  AuthErrorMapper._();

  /// Maps any exception or error object to a clean user-facing string.
  static String mapMessage(Object error) {
    if (error is DioException) {
      final response = error.response;
      if (response != null && response.data != null && response.data is Map) {
        final errorMsg = response.data['error'];
        if (errorMsg != null && errorMsg is String) {
          return errorMsg;
        }
      }
      
      final type = error.type;
      if (type == DioExceptionType.connectionTimeout ||
          type == DioExceptionType.receiveTimeout ||
          type == DioExceptionType.sendTimeout) {
        return 'Connection timeout. Please check your internet connection and try again.';
      }
      if (type == DioExceptionType.connectionError) {
        return 'Network connection error. Please check your internet connection.';
      }
      return 'Failed to reach server. Please try again later.';
    }

    final rawMessage = error.toString().toLowerCase();
    if (rawMessage.contains('invalid verification code') || 
        rawMessage.contains('expired')) {
      return 'Incorrect or expired verification code. Please try again.';
    }
    if (rawMessage.contains('phone number') || rawMessage.contains('phone')) {
      return 'Invalid phone number format. Please enter a valid number.';
    }

    return 'An unexpected error occurred. Please try again.';
  }
}

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
        if (errorMsg != null && errorMsg is String && errorMsg.trim().isNotEmpty) {
          return errorMsg;
        }
      }
      
      final type = error.type;
      if (type == DioExceptionType.connectionTimeout ||
          type == DioExceptionType.receiveTimeout ||
          type == DioExceptionType.sendTimeout) {
        return 'Connection timeout. The server took too long to respond. Please try again.';
      }
      if (type == DioExceptionType.connectionError) {
        return 'Network connection error. Please check your internet connection.';
      }
      return 'Failed to reach server. Please try again later.';
    }

    final rawMessage = error.toString();
    final lowerMessage = rawMessage.toLowerCase();

    if (lowerMessage.contains('connection timeout') ||
        lowerMessage.contains('connecttimeout') ||
        lowerMessage.contains('receivetimeout') ||
        lowerMessage.contains('sendtimeout') ||
        lowerMessage.contains('timeoutexception') ||
        lowerMessage.contains('took longer than')) {
      return 'Connection timeout. The server took too long to respond. Please try again.';
    }

    if (lowerMessage.contains('socketexception') ||
        lowerMessage.contains('connection error') ||
        lowerMessage.contains('failed host lookup') ||
        lowerMessage.contains('connection refused') ||
        lowerMessage.contains('network error')) {
      return 'Network connection error. Please check your internet connection.';
    }

    if (lowerMessage.contains('invalid verification code') || 
        lowerMessage.contains('expired')) {
      return 'Incorrect or expired verification code. Please try again.';
    }

    if (lowerMessage.contains('phone number') || lowerMessage.contains('phone')) {
      return 'Invalid whatsapp number format. Please enter a valid number.';
    }

    final cleaned = rawMessage
        .replaceAll('Exception: ', '')
        .replaceAll('DioException: ', '')
        .trim();

    if (cleaned.isNotEmpty && !cleaned.startsWith('DioException [')) {
      return cleaned;
    }

    return 'An unexpected error occurred. Please try again.';
  }
}

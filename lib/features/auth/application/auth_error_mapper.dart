import 'package:supabase_flutter/supabase_flutter.dart';

/// AuthErrorMapper handles converting technical AuthException errors into
/// user-friendly, localized error messages.
class AuthErrorMapper {
  AuthErrorMapper._();

  /// Maps any exception or error object to a clean user-facing string.
  static String mapMessage(Object error) {
    if (error is AuthException) {
      final code = error.statusCode;
      final rawMessage = error.message.toLowerCase();

      if (rawMessage.contains('email already registered') || 
          rawMessage.contains('user already exists') ||
          rawMessage.contains('signup_disabled')) {
        return 'This email address is already registered.';
      }
      if (rawMessage.contains('database error saving new user')) {
        return 'Something went wrong during signup, please try again.';
      }
      if (rawMessage.contains('invalid login credentials') || 
          rawMessage.contains('invalid credentials')) {
        return 'Incorrect email or password. Please try again.';
      }
      if (rawMessage.contains('email not confirmed')) {
        return 'Please confirm your email address to log in.';
      }
      if (rawMessage.contains('network') || rawMessage.contains('connection')) {
        return 'Network connection error. Please check your internet connection and try again.';
      }
      if (rawMessage.contains('too many requests') || code == '429') {
        return 'Too many attempts. Please try again in a few minutes.';
      }
      if (rawMessage.contains('password should be') || rawMessage.contains('password is too short')) {
        return 'Password must be at least 6 characters long.';
      }
      if (rawMessage.contains('invalid email')) {
        return 'Please enter a valid email address.';
      }

      return error.message; // Fallback to raw message if not customized
    }

    return 'An unexpected error occurred. Please try again.';
  }
}

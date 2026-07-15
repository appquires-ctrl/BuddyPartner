import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// AuthController coordinates client-side authentication triggers
/// against the Supabase backend.
class AuthController extends AutoDisposeAsyncNotifier<void> {
  @override
  FutureOr<void> build() {
    // Initial state is idle (AsyncData(null))
  }

  /// Sign in using email and password.
  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
    });
    if (result.hasError) {
      state = AsyncError(result.error!, result.stackTrace!);
      return false;
    }
    state = const AsyncData(null);
    return true;
  }

  /// Sign up a new user, attaching profile metadata that the DB trigger reads.
  Future<bool> signUp({
    required String email,
    required String password,
    required String fullName,
    required DateTime dob,
    required String gender,
    required String language,
  }) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          'dob': dob.toIso8601String(),
          'gender': gender,
          'language': language,
        },
      );
    });
    if (result.hasError) {
      state = AsyncError(result.error!, result.stackTrace!);
      return false;
    }
    state = const AsyncData(null);
    return true;
  }

  /// Trigger a password reset email for the user.
  Future<bool> resetPassword({required String email}) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
    });
    if (result.hasError) {
      state = AsyncError(result.error!, result.stackTrace!);
      return false;
    }
    state = const AsyncData(null);
    return true;
  }

  /// Log out of the current session.
  Future<void> signOut() async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      await Supabase.instance.client.auth.signOut();
    });
    if (result.hasError) {
      state = AsyncError(result.error!, result.stackTrace!);
    } else {
      state = const AsyncData(null);
    }
  }
}

/// Provider definition for AuthController.
final authControllerProvider =
    AutoDisposeAsyncNotifierProvider<AuthController, void>(AuthController.new);

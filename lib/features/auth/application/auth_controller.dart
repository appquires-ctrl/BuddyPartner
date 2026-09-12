import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/services/api_client.dart';
import 'package:buddypartner/core/services/apptrove_service.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';

/// AuthController coordinates client-side authentication triggers
/// against the custom Node.js/Neon backend via Authkey WhatsApp OTP.
class AuthController extends AutoDisposeAsyncNotifier<void> {
  @override
  FutureOr<void> build() {
    // Initial state is idle (AsyncData(null))
  }

  /// Request WhatsApp OTP to the provided country code and mobile number.
  Future<bool> sendOtp({required String countryCode, required String mobile}) async {
    state = const AsyncLoading();
    final apiClient = ref.read(apiClientProvider);

    try {
      final response = await apiClient.dio.post(
        '/api/auth/otp/send',
        data: {
          'country_code': countryCode.trim().replaceAll('+', ''),
          'mobile': mobile.trim(),
        },
      );

      if (response.statusCode == 200 && response.data != null && response.data['success'] == true) {
        state = const AsyncData(null);
        return true;
      } else {
        final errMsg = response.data?['error'] ?? 'Failed to send WhatsApp verification code.';
        state = AsyncError(Exception(errMsg), StackTrace.current);
        return false;
      }
    } catch (e, stack) {
      final errMsg = (e is DioException && e.response?.data is Map)
          ? e.response?.data['error'] ?? 'Failed to send WhatsApp OTP code.'
          : e.toString();
      state = AsyncError(Exception(errMsg), stack);
      return false;
    }
  }

  /// Verify the 6-digit WhatsApp OTP with the backend and trade for access + refresh tokens.
  /// Returns a Map containing verification result:
  /// - 'success': bool
  /// - 'isProfileComplete': bool
  /// - 'error': String? (if failed)
  Future<Map<String, dynamic>> verifyOtp({
    required String countryCode,
    required String mobile,
    required String otp,
  }) async {
    state = const AsyncLoading();
    final apiClient = ref.read(apiClientProvider);

    try {
      final response = await apiClient.dio.post(
        '/api/auth/otp/verify',
        data: {
          'country_code': countryCode.trim().replaceAll('+', ''),
          'mobile': mobile.trim(),
          'otp': otp.trim(),
        },
      );

      if (response.statusCode == 200 && response.data != null && response.data['success'] == true) {
        final token = response.data['token'] as String;
        final refreshToken = response.data['refreshToken'] as String;
        final isProfileComplete = response.data['isProfileComplete'] as bool? ?? false;

        // Save backend access and refresh tokens locally
        await apiClient.saveTokens(token: token, refreshToken: refreshToken);

        // Extract user directly from response payload (instant login without extra roundtrip)
        Map<String, dynamic>? userMap = response.data['user'] as Map<String, dynamic>?;
        if (userMap == null) {
          try {
            final userProfileResponse = await apiClient.dio.get('/api/auth/me');
            if (userProfileResponse.statusCode == 200 && userProfileResponse.data != null) {
              userMap = userProfileResponse.data['user'] as Map<String, dynamic>?;
            }
          } catch (_) {}
        }

        final user = CustomUser.fromBackendUserMap(
          userMap ?? {},
          isProfileComplete: isProfileComplete,
          fallbackPhone: '+$countryCode$mobile',
        );

        await ref.read(authStateProvider.notifier).setSession(user);

        // Track Login event in Apptrove
        AppTroveService.trackLogin(
          phoneNumber: user.phoneNumber,
          userId: user.id,
        );

        state = const AsyncData(null);
        return {
          'success': true,
          'isProfileComplete': isProfileComplete,
        };
      }

      final errMsg = response.data?['error'] ?? 'Invalid or expired verification code.';
      state = AsyncError(Exception(errMsg), StackTrace.current);
      return {'success': false, 'error': errMsg};
    } catch (e, stack) {
      final errMsg = (e is DioException && e.response?.data is Map)
          ? e.response?.data['error'] ?? 'Invalid or expired verification code.'
          : e.toString();
      state = AsyncError(Exception(errMsg), stack);
      return {'success': false, 'error': errMsg};
    }
  }

  /// Update profile metadata for onboarding completion.
  Future<bool> completeProfile({
    required String fullName,
    required DateTime dob,
    required String gender,
    required String language,
    String? avatarSeed,
    String? avatarStyle,
    bool? isTelecaller,
  }) async {
    state = const AsyncLoading();
    final apiClient = ref.read(apiClientProvider);

    final result = await AsyncValue.guard(() async {
      final response = await apiClient.dio.post(
        '/api/auth/profile',
        data: {
          'fullName': fullName,
          'dob': dob.toIso8601String(),
          'gender': gender,
          'language': language,
          'avatarSeed': avatarSeed,
          'avatarStyle': avatarStyle ?? 'avataaars',
          'isTelecaller': isTelecaller,
        },
      );

      if (response.statusCode != 200) {
        throw Exception(response.data['error'] ?? 'Failed to update profile.');
      }

      // Fetch updated profile state and update session notifier
      final userProfileResponse = await apiClient.dio.get('/api/auth/me');
      if (userProfileResponse.statusCode == 200 && userProfileResponse.data != null) {
        final userMap = userProfileResponse.data['user'] as Map<String, dynamic>? ?? {};
        final user = CustomUser.fromBackendUserMap(
          userMap,
          isProfileComplete: true,
          fallbackFullName: fullName,
          fallbackGender: gender,
          fallbackDob: dob,
          fallbackLanguage: language,
          fallbackAvatarSeed: avatarSeed,
          fallbackAvatarStyle: avatarStyle,
          fallbackIsTelecaller: isTelecaller,
        );
        await ref.read(authStateProvider.notifier).setSession(user);
      }

      final currentUser = ref.read(authStateProvider).value;
      final phone = currentUser?.phoneNumber;
      final userId = currentUser?.id;

      // Calculate user age from DOB
      final now = DateTime.now();
      int age = now.year - dob.year;
      if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
        age--;
      }

      // Track Sign-Up / Registration completion event in Apptrove
      AppTroveService.trackSignUp(
        userId: userId,
        phoneNumber: phone,
        gender: gender,
        language: language,
        fullName: fullName.trim(),
        dob: dob,
        age: age,
      );

      // Refresh userProfileProvider to notify profile widget listeners
      Future.microtask(() => ref.invalidate(userProfileProvider));
    });

    if (result.hasError) {
      try {
        state = AsyncError(result.error!, result.stackTrace!);
      } catch (_) {}
      return false;
    }

    try {
      state = const AsyncData(null);
    } catch (_) {}
    return true;
  }

  /// Update telecaller opt-in status (female users only).
  Future<bool> updateTelecallerStatus(bool isTelecaller) async {
    state = const AsyncLoading();
    final apiClient = ref.read(apiClientProvider);

    final result = await AsyncValue.guard(() async {
      final response = await apiClient.dio.patch(
        '/api/users/me/telecaller-status',
        data: {'isTelecaller': isTelecaller},
      );

      if (response.statusCode != 200) {
        throw Exception(response.data['error'] ?? 'Failed to update telecaller status.');
      }

      final currentUser = ref.read(authStateProvider).value;
      if (currentUser != null) {
        await ref.read(authStateProvider.notifier).setSession(
          currentUser.copyWith(isTelecaller: isTelecaller),
        );
      }

      Future.microtask(() => ref.invalidate(userProfileProvider));
    });

    if (result.hasError) {
      try {
        state = AsyncError(result.error!, result.stackTrace!);
      } catch (_) {}
      return false;
    }

    try {
      state = const AsyncData(null);
    } catch (_) {}
    return true;
  }

  /// Log out of the current session with 0ms optimistic UI transition.
  Future<void> signOut() async {
    final apiClient = ref.read(apiClientProvider);

    try {
      final refreshToken = await apiClient.getRefreshToken();
      if (refreshToken != null && refreshToken.isNotEmpty) {
        // Notify backend concurrently in background without blocking UI navigation
        unawaited(() async {
          try {
            await apiClient.dio.post('/api/auth/logout', data: {'refreshToken': refreshToken});
          } catch (_) {}
        }());
      }
    } catch (_) {}

    // Immediately clear local session, socket, and tokens
    await ref.read(authStateProvider.notifier).clearSession();
    state = const AsyncData(null);
  }

  /// Permanently delete user account and wipe session state.
  Future<bool> deleteAccount({required String reason, String? feedback}) async {
    final apiClient = ref.read(apiClientProvider);
    state = const AsyncLoading();

    try {
      // 1. Send delete account request to backend
      try {
        await apiClient.dio.post(
          '/api/auth/delete-account',
          data: {
            'reason': reason,
            if (feedback != null && feedback.trim().isNotEmpty) 'feedback': feedback.trim(),
          },
        );
      } catch (_) {
        // Also try DELETE /api/users/me as fallback
        try {
          await apiClient.dio.delete(
            '/api/users/me',
            data: {
              'reason': reason,
              if (feedback != null && feedback.trim().isNotEmpty) 'feedback': feedback.trim(),
            },
          );
        } catch (_) {}
      }

      // 2. Clear local session, socket connection, tokens, and invalidate all caches
      await ref.read(authStateProvider.notifier).clearSession();
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      await ref.read(authStateProvider.notifier).clearSession();
      state = AsyncError(e, st);
      return false;
    }
  }
}


/// Provider definition for AuthController.
final authControllerProvider =
    AutoDisposeAsyncNotifierProvider<AuthController, void>(AuthController.new);

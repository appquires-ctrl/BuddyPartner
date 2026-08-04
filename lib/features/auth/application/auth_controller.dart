import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dating_app/core/services/api_client.dart';
import 'package:dating_app/features/auth/application/auth_state_provider.dart';

/// AuthController coordinates client-side authentication triggers
/// against the custom Node.js/Neon backend.
class AuthController extends AutoDisposeAsyncNotifier<void> {
  String? _verificationId;
  int? _resendToken;

  @override
  FutureOr<void> build() {
    // Initial state is idle (AsyncData(null))
  }

  /// Request SMS OTP to the provided phone number using Firebase Auth.
  Future<bool> sendOtp(String phone) async {
    state = const AsyncLoading();
    final completer = Completer<bool>();
    
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
            final idToken = await userCredential.user?.getIdToken();
            if (idToken != null) {
              final loginSuccess = await _loginToBackend(phone, idToken);
              if (loginSuccess && !completer.isCompleted) {
                completer.complete(true);
              }
            }
          } catch (e) {
            if (!completer.isCompleted) {
              completer.completeError(e);
            }
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!completer.isCompleted) {
            completer.completeError(Exception(e.message ?? 'Firebase Phone verification failed.'));
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          _resendToken = resendToken;
          state = const AsyncData(null);
          if (!completer.isCompleted) {
            completer.complete(true);
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
        forceResendingToken: _resendToken,
      );
    } catch (e, stack) {
      state = AsyncError(e, stack);
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    }
    
    return completer.future;
  }

  /// Helper to exchange the verified Firebase IdToken for our backend JWT token.
  Future<bool> _loginToBackend(String phone, String idToken) async {
    final apiClient = ref.read(apiClientProvider);
    final response = await apiClient.dio.post(
      '/api/auth/firebase-login',
      data: {'phone': phone, 'idToken': idToken},
    );
    
    if (response.statusCode == 200 && response.data != null) {
      final token = response.data['token'] as String;
      final isProfileComplete = response.data['isProfileComplete'] as bool? ?? false;
      
      // Save backend token
      await apiClient.saveToken(token);
      
      // Fetch profile
      try {
        final userProfileResponse = await apiClient.dio.get('/api/auth/me');
        if (userProfileResponse.statusCode == 200 && userProfileResponse.data != null) {
          final userMap = userProfileResponse.data['user'];
          ref.read(authStateProvider.notifier).setSession(
            CustomUser(
              id: userMap['id'] as String,
              phoneNumber: userMap['phoneNumber'] as String,
              isProfileComplete: isProfileComplete,
              gender: userMap['gender'] as String? ?? 'Male',
            ),
          );
          return true;
        }
      } catch (e) {
        if (e is DioException && e.response?.statusCode == 403) {
          // Account is Banned or Suspended: Interceptor automatically routes to RouteNames.banned screen
          return false;
        }
        rethrow;
      }
    }
    return false;
  }

  /// Verify the OTP with Firebase and trade for a backend session token.
  /// Returns a Map containing verification result:
  /// - 'success': bool
  /// - 'isProfileComplete': bool (if user already filled metadata)
  Future<Map<String, dynamic>> verifyOtp(String phone, String otp) async {
    state = const AsyncLoading();
    
    try {
      if (_verificationId == null) {
        throw Exception("Verification ID is missing. Please send OTP first.");
      }
      
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: otp,
      );
      
      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final idToken = await userCredential.user?.getIdToken();
      if (idToken == null) {
        throw Exception("Failed to retrieve Firebase authentication token.");
      }
      
      final success = await _loginToBackend(phone, idToken);
      state = const AsyncData(null);
      return {
        'success': success,
        'isProfileComplete': ref.read(authStateProvider).value?.isProfileComplete ?? false,
      };
    } catch (e, stack) {
      state = AsyncError(e, stack);
      return {'success': false, 'error': e.toString()};
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
          if (isTelecaller != null) 'isTelecaller': isTelecaller,
        },
      );
      
      if (response.statusCode != 200) {
        throw Exception(response.data['error'] ?? 'Failed to update profile.');
      }
      
      // Fetch updated profile state and update session notifier
      final userProfileResponse = await apiClient.dio.get('/api/auth/me');
      if (userProfileResponse.statusCode == 200 && userProfileResponse.data != null) {
        final userMap = userProfileResponse.data['user'];
        ref.read(authStateProvider.notifier).setSession(
          CustomUser(
            id: userMap['id'] as String,
            phoneNumber: userMap['phoneNumber'] as String,
            isProfileComplete: true,
            gender: userMap['gender'] as String? ?? 'Male',
            avatarSeed: userMap['avatarSeed'] as String?,
            avatarStyle: userMap['avatarStyle'] as String? ?? 'avataaars',
            isTelecaller: userMap['isTelecaller'] as bool?,
          ),
        );
      }
      
      // Refresh userProfileProvider to notify profile widget listeners
      ref.invalidate(userProfileProvider);
    });

    if (result.hasError) {
      state = AsyncError(result.error!, result.stackTrace!);
      return false;
    }
    
    state = const AsyncData(null);
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
        ref.read(authStateProvider.notifier).setSession(
          currentUser.copyWith(isTelecaller: isTelecaller),
        );
      }

      ref.invalidate(userProfileProvider);
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
    try {
      await FirebaseAuth.instance.signOut();
      await ref.read(authStateProvider.notifier).clearSession();
    } catch (_) {
      // Controller auto-disposes on route transition when session clears
    }
  }
}

/// Provider definition for AuthController.
final authControllerProvider =
    AutoDisposeAsyncNotifierProvider<AuthController, void>(AuthController.new);

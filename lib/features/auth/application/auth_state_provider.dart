import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dating_app/core/services/api_client.dart';

class CustomUser {
  final String id;
  final String phoneNumber;
  final bool isProfileComplete;
  final String gender;
  final String? avatarSeed;
  final String? avatarStyle;

  CustomUser({
    required this.id,
    required this.phoneNumber,
    required this.isProfileComplete,
    required this.gender,
    this.avatarSeed,
    this.avatarStyle,
  });

  /// Convenience getters for gender-based routing
  bool get isFemale {
    final g = gender.toLowerCase();
    return g == 'female' || g == 'girl' || g == 'woman';
  }

  bool get isMale => !isFemale;
}

class AuthNotifier extends AsyncNotifier<CustomUser?> {
  @override
  FutureOr<CustomUser?> build() async {
    final apiClient = ref.watch(apiClientProvider);
    final hasToken = await apiClient.hasToken();
    if (!hasToken) return null;

    try {
      final response = await apiClient.dio.get('/api/auth/me');
      if (response.statusCode == 200 && response.data != null) {
        final userMap = response.data['user'];
        final fullName = userMap['fullName'] as String? ?? '';
        final gender = userMap['gender'] as String? ?? 'Male';
        return CustomUser(
          id: userMap['id'] as String,
          phoneNumber: userMap['phoneNumber'] as String,
          isProfileComplete: fullName.trim().isNotEmpty,
          gender: gender,
          avatarSeed: userMap['avatarSeed'] as String?,
          avatarStyle: userMap['avatarStyle'] as String? ?? 'avataaars',
        );
      }
    } catch (e) {
      // In case token is invalid, delete it
      await apiClient.deleteToken();
    }
    return null;
  }

  /// Sets user state manually on successful verification
  void setSession(CustomUser? user) {
    state = AsyncData(user);
  }

  /// Clears the session
  Future<void> clearSession() async {
    state = const AsyncLoading();
    await ref.read(apiClientProvider).deleteToken();
    state = const AsyncData(null);
  }
}

final authStateProvider = AsyncNotifierProvider<AuthNotifier, CustomUser?>(AuthNotifier.new);

/// A convenience provider to quickly check if a user is authenticated.
final isAuthenticatedProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.value != null;
});

/// UserProfile model maps profile rows from public.users
class UserProfile {
  final String id;
  final String fullName;
  final DateTime dob;
  final String gender;
  final String language;
  final String? avatarSeed;
  final String? avatarStyle;

  UserProfile({
    required this.id,
    required this.fullName,
    required this.dob,
    required this.gender,
    required this.language,
    this.avatarSeed,
    this.avatarStyle,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      fullName: json['fullName'] as String? ?? 'User',
      dob: DateTime.tryParse(json['dob'] as String? ?? '') ?? DateTime.now(),
      gender: json['gender'] as String? ?? 'Other',
      language: json['language'] as String? ?? 'English',
      avatarSeed: json['avatarSeed'] as String?,
      avatarStyle: json['avatarStyle'] as String? ?? 'avataaars',
    );
  }
}

/// Fetches the user profile row corresponding to the currently authenticated user
final userProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final authState = ref.watch(authStateProvider);
  final user = authState.value;
  if (user == null) return null;

  try {
    final apiClient = ref.watch(apiClientProvider);
    final response = await apiClient.dio.get('/api/auth/me');

    if (response.data == null || response.data['user'] == null) return null;
    return UserProfile.fromJson(response.data['user'] as Map<String, dynamic>);
  } catch (e) {
    return null;
  }
});

/// Helper utility to extract initials from name
String getInitials(String name) {
  if (name.trim().isEmpty) return 'U';
  final parts = name.trim().toUpperCase().split(RegExp(r'\s+'));
  if (parts.length > 1) {
    return '${parts[0][0]}${parts[1][0]}';
  }
  return parts[0].isNotEmpty ? parts[0][0] : 'U';
}

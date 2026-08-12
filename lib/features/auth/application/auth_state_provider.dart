import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/services/api_client.dart';
import 'package:buddypartner/core/services/socket_provider.dart';
import 'package:buddypartner/features/chat/application/presence_provider.dart';
import 'package:buddypartner/features/chat/application/conversations_provider.dart';
import 'package:buddypartner/features/subscription/application/subscription_providers.dart';
import 'package:buddypartner/features/call/application/matchmaking_controller.dart';
import 'package:buddypartner/features/call/application/call_summary_provider.dart';
import 'package:buddypartner/features/withdraw/application/rose_providers.dart';
import 'package:buddypartner/features/withdraw/application/withdraw_controller.dart';
import 'package:buddypartner/features/home/presentation/providers/matched_users_provider.dart';
import 'package:buddypartner/features/history/data/call_history_provider.dart';

class CustomUser {
  final String id;
  final String phoneNumber;
  final bool isProfileComplete;
  final String gender;
  final String? fullName;
  final String? avatarSeed;
  final String? avatarStyle;
  final bool? isTelecaller;
  final bool hasClaimedIntroOffer;

  CustomUser({
    required this.id,
    required this.phoneNumber,
    required this.isProfileComplete,
    required this.gender,
    this.fullName,
    this.avatarSeed,
    this.avatarStyle,
    this.isTelecaller,
    this.hasClaimedIntroOffer = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phoneNumber': phoneNumber,
      'isProfileComplete': isProfileComplete,
      'gender': gender,
      'fullName': fullName,
      'avatarSeed': avatarSeed,
      'avatarStyle': avatarStyle,
      'isTelecaller': isTelecaller,
      'hasClaimedIntroOffer': hasClaimedIntroOffer,
    };
  }

  factory CustomUser.fromJson(Map<String, dynamic> json) {
    return CustomUser(
      id: json['id'] as String? ?? '',
      phoneNumber: json['phoneNumber'] as String? ?? '',
      isProfileComplete: json['isProfileComplete'] as bool? ?? false,
      gender: json['gender'] as String? ?? 'Male',
      fullName: json['fullName'] as String?,
      avatarSeed: json['avatarSeed'] as String?,
      avatarStyle: json['avatarStyle'] as String? ?? 'avataaars',
      isTelecaller: json['isTelecaller'] as bool?,
      hasClaimedIntroOffer: json['hasClaimedIntroOffer'] as bool? ?? false,
    );
  }

  /// Convenience getters for gender-based routing
  bool get isFemale {
    final g = gender.toLowerCase();
    return g == 'female' || g == 'girl' || g == 'woman';
  }

  bool get isMale => !isFemale;

  /// Returns whether this female user is an active Telecaller
  bool get isTelecallerActive => isFemale && (isTelecaller == true);

  CustomUser copyWith({
    String? id,
    String? phoneNumber,
    bool? isProfileComplete,
    String? gender,
    String? fullName,
    String? avatarSeed,
    String? avatarStyle,
    bool? isTelecaller,
    bool? hasClaimedIntroOffer,
  }) {
    return CustomUser(
      id: id ?? this.id,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      isProfileComplete: isProfileComplete ?? this.isProfileComplete,
      gender: gender ?? this.gender,
      fullName: fullName ?? this.fullName,
      avatarSeed: avatarSeed ?? this.avatarSeed,
      avatarStyle: avatarStyle ?? this.avatarStyle,
      isTelecaller: isTelecaller ?? this.isTelecaller,
      hasClaimedIntroOffer: hasClaimedIntroOffer ?? this.hasClaimedIntroOffer,
    );
  }
}

class AuthNotifier extends AsyncNotifier<CustomUser?> {
  @override
  FutureOr<CustomUser?> build() async {
    final apiClient = ref.watch(apiClientProvider);
    final hasToken = await apiClient.hasToken();
    if (!hasToken) return null;

    // Load cached session instantly from platform secure storage
    CustomUser? cachedUser;
    final cachedMap = await apiClient.getUserSessionJson();
    if (cachedMap != null) {
      try {
        cachedUser = CustomUser.fromJson(cachedMap);
      } catch (_) {}
    }

    // Asynchronously revalidate session against backend in background
    _revalidateSession(apiClient);

    return cachedUser;
  }

  Future<void> _revalidateSession(ApiClient apiClient) async {
    try {
      final response = await apiClient.dio.get('/api/auth/me');
      if (response.statusCode == 200 && response.data != null) {
        final userMap = response.data['user'];
        final fullName = userMap['fullName'] as String? ?? '';
        final gender = userMap['gender'] as String? ?? 'Male';
        final freshUser = CustomUser(
          id: userMap['id'] as String,
          phoneNumber: userMap['phoneNumber'] as String,
          isProfileComplete: fullName.trim().isNotEmpty,
          gender: gender,
          fullName: fullName.trim().isNotEmpty ? fullName.trim() : null,
          avatarSeed: userMap['avatarSeed'] as String?,
          avatarStyle: userMap['avatarStyle'] as String? ?? 'avataaars',
          isTelecaller: userMap['isTelecaller'] as bool?,
          hasClaimedIntroOffer: userMap['hasClaimedIntroOffer'] as bool? ?? false,
        );

        await apiClient.saveUserSessionJson(freshUser.toJson());
        state = AsyncData(freshUser);
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        // Session explicitly revoked or expired
        await apiClient.deleteTokens();
        state = const AsyncData(null);
      }
    } catch (_) {
      // Preserve cached session for offline/network errors
    }
  }

  /// Sets user state manually on successful verification
  Future<void> setSession(CustomUser? user) async {
    final apiClient = ref.read(apiClientProvider);
    if (user != null) {
      await apiClient.saveUserSessionJson(user.toJson());
    } else {
      await apiClient.deleteUserSessionJson();
    }
    state = AsyncData(user);
    if (user != null) {
      Future.microtask(() {
        ref.invalidate(subscriptionStatusProvider);
        ref.invalidate(userProfileProvider);
        ref.invalidate(conversationsProvider);
        ref.invalidate(presenceProvider);
        ref.invalidate(matchedUsersProvider);
        ref.invalidate(favoriteUsersProvider);
        ref.invalidate(callHistoryProvider);
      });
    }
  }

  /// Clears the session and disconnects real-time socket & presence states
  Future<void> clearSession() async {
    try {
      // Explicitly disconnect and dispose real-time Socket.io connection on backend
      ref.read(socketProvider.notifier).disconnectAndDispose();

      // Clear local auth tokens and cached user session
      await ref.read(apiClientProvider).deleteTokens();

      // Clear session state to notify GoRouter and state listeners
      state = const AsyncData(null);

      // Invalidate all user-specific provider caches safely in microtask
      Future.microtask(() {
        ref.invalidate(presenceProvider);
        ref.invalidate(conversationsProvider);
        ref.invalidate(userProfileProvider);
        ref.invalidate(subscriptionStatusProvider);
        ref.invalidate(matchmakingControllerProvider);
        ref.invalidate(lastCallSummaryProvider);
        ref.invalidate(withdrawalHistoryProvider);
        ref.invalidate(withdrawControllerProvider);
        ref.invalidate(matchedUsersProvider);
        ref.invalidate(favoriteUsersProvider);
        ref.invalidate(callHistoryProvider);
      });
    } catch (e) {
      state = const AsyncData(null);
    }
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
  final bool? isTelecaller;
  final bool hasClaimedIntroOffer;
  final String? country;
  final String? state;
  final String? city;
  final double? latitude;
  final double? longitude;

  UserProfile({
    required this.id,
    required this.fullName,
    required this.dob,
    required this.gender,
    required this.language,
    this.avatarSeed,
    this.avatarStyle,
    this.isTelecaller,
    this.hasClaimedIntroOffer = false,
    this.country,
    this.state,
    this.city,
    this.latitude,
    this.longitude,
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
      isTelecaller: json['isTelecaller'] as bool?,
      hasClaimedIntroOffer: json['hasClaimedIntroOffer'] as bool? ?? false,
      country: json['country'] as String?,
      state: json['state'] as String?,
      city: json['city'] as String?,
      latitude: (json['latitude'] != null) ? (json['latitude'] as num).toDouble() : null,
      longitude: (json['longitude'] != null) ? (json['longitude'] as num).toDouble() : null,
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
    final profile = UserProfile.fromJson(response.data['user'] as Map<String, dynamic>);
    if (profile.id != user.id) return null;
    return profile;
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

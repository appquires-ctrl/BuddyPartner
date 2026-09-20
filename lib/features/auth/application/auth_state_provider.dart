import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/services/api_client.dart';
import 'package:buddypartner/core/services/apptrove_service.dart';
import 'package:buddypartner/core/services/socket_provider.dart';

class CustomUser {
  final String id;
  final String phoneNumber;
  final bool isProfileComplete;
  final String gender;
  final String? fullName;
  final String? userName;
  final String? avatarSeed;
  final String? avatarStyle;
  final bool? isTelecaller;
  final bool hasClaimedIntroOffer;
  final DateTime? dob;
  final String? language;
  final String? country;
  final String? state;
  final String? city;
  final double? latitude;
  final double? longitude;
  final bool hasPassword;

  CustomUser({
    required this.id,
    required this.phoneNumber,
    required this.isProfileComplete,
    required this.gender,
    this.fullName,
    this.userName,
    this.avatarSeed,
    this.avatarStyle,
    this.isTelecaller,
    this.hasClaimedIntroOffer = false,
    this.dob,
    this.language,
    this.country,
    this.state,
    this.city,
    this.latitude,
    this.longitude,
    this.hasPassword = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phoneNumber': phoneNumber,
      'isProfileComplete': isProfileComplete,
      'gender': gender,
      'fullName': fullName,
      'userName': userName,
      'avatarSeed': avatarSeed,
      'avatarStyle': avatarStyle,
      'isTelecaller': isTelecaller,
      'hasClaimedIntroOffer': hasClaimedIntroOffer,
      'dob': dob?.toIso8601String(),
      'language': language,
      'country': country,
      'state': state,
      'city': city,
      'latitude': latitude,
      'longitude': longitude,
      'hasPassword': hasPassword,
    };
  }

  factory CustomUser.fromJson(Map<String, dynamic> json) {
    final rawFullName = (json['fullName'] as String?)?.trim();
    final bool hasName = rawFullName != null && rawFullName.isNotEmpty;
    return CustomUser(
      id: json['id'] as String? ?? '',
      phoneNumber: json['phoneNumber'] as String? ?? '',
      isProfileComplete: (json['isProfileComplete'] as bool? ?? false) || hasName,
      gender: json['gender'] as String? ?? 'Male',
      fullName: rawFullName,
      userName: (json['userName'] ?? json['user_name']) as String?,
      avatarSeed: json['avatarSeed'] as String?,
      avatarStyle: json['avatarStyle'] as String? ?? 'avataaars',
      isTelecaller: json['isTelecaller'] as bool?,
      hasClaimedIntroOffer: json['hasClaimedIntroOffer'] as bool? ?? false,
      dob: DateTime.tryParse(json['dob'] as String? ?? ''),
      language: json['language'] as String?,
      country: json['country'] as String?,
      state: json['state'] as String?,
      city: json['city'] as String?,
      latitude: (json['latitude'] != null) ? (json['latitude'] as num).toDouble() : null,
      longitude: (json['longitude'] != null) ? (json['longitude'] as num).toDouble() : null,
      hasPassword: json['hasPassword'] as bool? ?? false,
    );
  }

  /// Factory to construct CustomUser from the backend `user` map returned by
  /// /api/auth/otp/verify or /api/auth/me, ensuring all profile metadata fields are mapped.
  factory CustomUser.fromBackendUserMap(
    Map<String, dynamic> userMap, {
    bool isProfileComplete = false,
    String? fallbackPhone,
    String? fallbackFullName,
    String? fallbackUserName,
    String? fallbackGender,
    DateTime? fallbackDob,
    String? fallbackLanguage,
    String? fallbackAvatarSeed,
    String? fallbackAvatarStyle,
    bool? fallbackIsTelecaller,
  }) {
    final rawFullName = (userMap['fullName'] ?? userMap['full_name'] ?? fallbackFullName ?? '').toString().trim();
    final rawUserName = (userMap['userName'] ?? userMap['user_name'] ?? fallbackUserName) as String?;
    final rawPhone = userMap['phoneNumber'] as String? ?? fallbackPhone ?? '';
    final parsedDob = DateTime.tryParse(userMap['dob'] as String? ?? '') ?? fallbackDob;
    final backendIsComplete = (userMap['isProfileComplete'] as bool?) ?? isProfileComplete;
    final effectiveIsComplete = backendIsComplete || rawFullName.isNotEmpty;

    return CustomUser(
      id: userMap['id'] as String? ?? '',
      phoneNumber: rawPhone,
      isProfileComplete: effectiveIsComplete,
      gender: userMap['gender'] as String? ?? fallbackGender ?? 'Male',
      fullName: rawFullName.isNotEmpty ? rawFullName : null,
      userName: rawUserName != null && rawUserName.trim().isNotEmpty ? rawUserName.trim().toLowerCase() : null,
      avatarSeed: userMap['avatarSeed'] as String? ?? fallbackAvatarSeed,
      avatarStyle: userMap['avatarStyle'] as String? ?? fallbackAvatarStyle ?? 'avataaars',
      isTelecaller: userMap['isTelecaller'] as bool? ?? fallbackIsTelecaller,
      hasClaimedIntroOffer: userMap['hasClaimedIntroOffer'] as bool? ?? false,
      dob: parsedDob,
      language: userMap['language'] as String? ?? fallbackLanguage ?? 'English',
      country: userMap['country'] as String?,
      state: userMap['state'] as String?,
      city: userMap['city'] as String?,
      latitude: (userMap['latitude'] != null) ? (userMap['latitude'] as num).toDouble() : null,
      longitude: (userMap['longitude'] != null) ? (userMap['longitude'] as num).toDouble() : null,
      hasPassword: userMap['hasPassword'] as bool? ?? false,
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
    String? userName,
    String? avatarSeed,
    String? avatarStyle,
    bool? isTelecaller,
    bool? hasClaimedIntroOffer,
    DateTime? dob,
    String? language,
    String? country,
    String? state,
    String? city,
    double? latitude,
    double? longitude,
    bool? hasPassword,
  }) {
    return CustomUser(
      id: id ?? this.id,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      isProfileComplete: isProfileComplete ?? this.isProfileComplete,
      gender: gender ?? this.gender,
      fullName: fullName ?? this.fullName,
      userName: userName ?? this.userName,
      avatarSeed: avatarSeed ?? this.avatarSeed,
      avatarStyle: avatarStyle ?? this.avatarStyle,
      isTelecaller: isTelecaller ?? this.isTelecaller,
      hasClaimedIntroOffer: hasClaimedIntroOffer ?? this.hasClaimedIntroOffer,
      dob: dob ?? this.dob,
      language: language ?? this.language,
      country: country ?? this.country,
      state: state ?? this.state,
      city: city ?? this.city,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      hasPassword: hasPassword ?? this.hasPassword,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomUser &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          phoneNumber == other.phoneNumber &&
          isProfileComplete == other.isProfileComplete &&
          gender == other.gender &&
          fullName == other.fullName &&
          userName == other.userName &&
          avatarSeed == other.avatarSeed &&
          avatarStyle == other.avatarStyle &&
          isTelecaller == other.isTelecaller &&
          hasClaimedIntroOffer == other.hasClaimedIntroOffer &&
          dob == other.dob &&
          language == other.language &&
          country == other.country &&
          state == other.state &&
          city == other.city &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          hasPassword == other.hasPassword;

  @override
  int get hashCode => Object.hash(
        id,
        phoneNumber,
        isProfileComplete,
        gender,
        fullName,
        userName,
        avatarSeed,
        avatarStyle,
        isTelecaller,
        hasClaimedIntroOffer,
        dob,
        language,
        country,
        state,
        city,
        latitude,
        longitude,
        hasPassword,
      );
}

class AuthNotifier extends AsyncNotifier<CustomUser?> {
  @override
  FutureOr<CustomUser?> build() async {
    try {
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

      // If we have a verified cached user with a complete profile, return it immediately for instant launch.
      // Revalidate in background to keep balances & data fresh.
      if (cachedUser != null && cachedUser.isProfileComplete) {
        _revalidateSession(apiClient);
        return cachedUser;
      }

      // If there is no cached user or the cached profile was marked incomplete,
      // await backend revalidation so SplashPage gets the authoritative profile before routing.
      try {
        final freshUser = await _revalidateSession(apiClient).timeout(const Duration(seconds: 4));
        if (freshUser != null) {
          return freshUser;
        }
      } catch (_) {}

      return cachedUser;
    } catch (_) {
      return null;
    }
  }

  Future<CustomUser?> _revalidateSession(ApiClient apiClient) async {
    try {
      final response = await apiClient.dio.get('/api/auth/me');
      if (response.statusCode == 200 && response.data != null) {
        final userMap = response.data['user'] as Map<String, dynamic>? ?? {};
        final fullName = (userMap['fullName'] ?? userMap['full_name'] ?? '').toString().trim();
        final bool isComplete = (response.data['isProfileComplete'] as bool?) ??
            (userMap['isProfileComplete'] as bool?) ??
            fullName.isNotEmpty;
        final freshUser = CustomUser.fromBackendUserMap(
          userMap,
          isProfileComplete: isComplete,
        );

        if (state.valueOrNull != freshUser) {
          state = AsyncData(freshUser);
        }
        await apiClient.saveUserSessionJson(freshUser.toJson());

        // Bind user attribution to Apptrove SDK
        AppTroveService.setUser(
          userId: freshUser.id,
          userPhone: freshUser.phoneNumber,
          userName: freshUser.fullName,
          gender: freshUser.gender,
          additionalDetails: {
            'isProfileComplete': freshUser.isProfileComplete,
          },
        );

        return freshUser;
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        // Session explicitly revoked or expired
        await apiClient.deleteTokens();
        state = const AsyncData(null);
      }
      return null;
    } catch (_) {
      // Preserve cached session for offline/network errors
      return null;
    }
  }

  /// Sets user state manually on successful verification
  Future<void> setSession(CustomUser? user) async {
    final apiClient = ref.read(apiClientProvider);
    if (user != null) {
      await apiClient.saveUserSessionJson(user.toJson());

      // Bind user attribution to Apptrove SDK
      AppTroveService.setUser(
        userId: user.id,
        userPhone: user.phoneNumber,
        userName: user.fullName,
        gender: user.gender,
        additionalDetails: {
          'isProfileComplete': user.isProfileComplete,
        },
      );
    } else {
      await apiClient.deleteUserSessionJson();
    }
    state = AsyncData(user);
  }

  /// Clears the session and disconnects real-time socket & presence states
  Future<void> clearSession() async {
    try {
      // 1. Explicitly disconnect and dispose real-time Socket.io connection
      ref.read(socketProvider.notifier).disconnectAndDispose();

      // 2. Clear local auth tokens and cached user session
      await ref.read(apiClientProvider).deleteTokens();

      // 3. Immediately set session state to null so GoRouter navigates instantly (0ms latency)
      state = const AsyncData(null);
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

/// Synchronously derives the user profile row corresponding to the currently authenticated user.
/// Eliminates redundant GET /api/auth/me call by sourcing directly from authStateProvider.
final userProfileProvider = Provider<UserProfile?>((ref) {
  final authState = ref.watch(authStateProvider);
  final user = authState.valueOrNull;
  if (user == null || user.id.isEmpty) return null;

  return UserProfile(
    id: user.id,
    fullName: (user.fullName != null && user.fullName!.trim().isNotEmpty) ? user.fullName!.trim() : 'User',
    dob: user.dob ?? DateTime.now(),
    gender: user.gender,
    language: user.language ?? 'English',
    avatarSeed: user.avatarSeed,
    avatarStyle: user.avatarStyle ?? 'avataaars',
    isTelecaller: user.isTelecaller,
    hasClaimedIntroOffer: user.hasClaimedIntroOffer,
    country: user.country,
    state: user.state,
    city: user.city,
    latitude: user.latitude,
    longitude: user.longitude,
  );
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

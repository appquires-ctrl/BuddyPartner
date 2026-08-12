import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/services/api_client.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';

class MatchedUser {
  final String id;
  final String fullName;
  final bool isOnline;
  final bool isFavorite;
  final String? avatarSeed;
  final String? avatarStyle;
  final String? gender;

  MatchedUser({
    required this.id,
    required this.fullName,
    required this.isOnline,
    required this.isFavorite,
    this.avatarSeed,
    this.avatarStyle,
    this.gender,
  });

  factory MatchedUser.fromJson(Map<String, dynamic> json) {
    return MatchedUser(
      id: json['id'] as String? ?? '',
      fullName: json['fullName'] as String? ?? 'User',
      isOnline: json['isOnline'] as bool? ?? false,
      isFavorite: json['isFavorite'] as bool? ?? false,
      avatarSeed: (json['avatarSeed'] ?? json['avatar_seed']) as String?,
      avatarStyle: (json['avatarStyle'] ?? json['avatar_style']) as String? ?? 'avataaars',
      gender: json['gender'] as String?,
    );
  }

  MatchedUser copyWith({
    String? id,
    String? fullName,
    bool? isOnline,
    bool? isFavorite,
    String? avatarSeed,
    String? avatarStyle,
    String? gender,
  }) {
    return MatchedUser(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      isOnline: isOnline ?? this.isOnline,
      isFavorite: isFavorite ?? this.isFavorite,
      avatarSeed: avatarSeed ?? this.avatarSeed,
      avatarStyle: avatarStyle ?? this.avatarStyle,
      gender: gender ?? this.gender,
    );
  }
}

final matchedUsersProvider = FutureProvider.autoDispose<List<MatchedUser>>((ref) async {
  final authState = ref.watch(authStateProvider);
  final user = authState.value;
  if (user == null) return const [];

  final apiClient = ref.watch(apiClientProvider);
  final response = await apiClient.dio.get('/api/calls/matches');
  if (response.data == null) return const [];
  final list = List<Map<String, dynamic>>.from(response.data as List);
  return list.map((json) => MatchedUser.fromJson(json)).toList();
});

final favoriteUsersProvider = FutureProvider.autoDispose<List<MatchedUser>>((ref) async {
  final authState = ref.watch(authStateProvider);
  final user = authState.value;
  if (user == null) return const [];

  final apiClient = ref.watch(apiClientProvider);
  final response = await apiClient.dio.get('/api/calls/favorites');
  if (response.data == null) return const [];
  final list = List<Map<String, dynamic>>.from(response.data as List);
  return list.map((json) => MatchedUser.fromJson(json)).toList();
});

class FavoritesNotifier extends AutoDisposeNotifier<void> {
  @override
  void build() {}

  Future<void> toggleFavorite(String targetUserId, bool isCurrentlyFavorite) async {
    final apiClient = ref.read(apiClientProvider);
    if (isCurrentlyFavorite) {
      // Remove from favorites
      await apiClient.dio.delete('/api/calls/favorites/$targetUserId');
    } else {
      // Add to favorites
      await apiClient.dio.post('/api/calls/favorites', data: {
        'favoriteUserId': targetUserId,
      });
    }
    // Invalidate matched users & favorites providers to refresh the lists
    ref.invalidate(matchedUsersProvider);
    ref.invalidate(favoriteUsersProvider);
  }
}

final favoritesNotifierProvider = AutoDisposeNotifierProvider<FavoritesNotifier, void>(
  FavoritesNotifier.new,
);

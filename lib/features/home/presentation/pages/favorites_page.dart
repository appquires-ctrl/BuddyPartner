import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/app/theme/app_spacing.dart';
import 'package:buddypartner/core/utils/app_logger.dart';
import 'package:buddypartner/core/services/api_client.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';
import 'package:buddypartner/features/home/presentation/widgets/matching_illustration.dart';
import 'package:buddypartner/features/home/presentation/providers/matched_users_provider.dart';
import 'package:buddypartner/features/home/presentation/widgets/favorite_user_card.dart';
import 'package:buddypartner/features/home/presentation/widgets/favorites_skeleton.dart';

/// FavoritesPage renders the user's favorited telecallers and supports
/// real-time debounced username search against the backend API.
class FavoritesPage extends ConsumerStatefulWidget {
  const FavoritesPage({super.key});

  @override
  ConsumerState<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends ConsumerState<FavoritesPage> {
  bool _isRefreshing = false;

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;
  int _activeRequestId = 0;

  List<MatchedUser>? _searchResults;
  bool _isSearching = false;
  String? _searchErrorMessage;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    final trimmed = query.trim();

    if (trimmed.length < 2) {
      setState(() {
        _isSearching = false;
        _searchResults = null;
        _searchErrorMessage = null;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _performSearch(trimmed);
    });
  }

  Future<void> _performSearch(String query) async {
    final requestId = ++_activeRequestId;
    setState(() {
      _isSearching = true;
      _searchErrorMessage = null;
    });

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.dio.get(
        '/api/users/search',
        queryParameters: {
          'query': query,
          'limit': 20,
        },
      );

      // Discard stale responses if user continued typing
      if (requestId != _activeRequestId || !mounted) return;

      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        final rawUsers = data['users'] as List? ?? [];
        final favoriteUsers = ref.read(favoriteUsersProvider).value ?? const [];
        final favoriteIds = favoriteUsers.map((u) => u.id).toSet();

        final currentUserId = ref.read(authStateProvider).value?.id;
        final results = rawUsers
            .map((u) {
              final map = Map<String, dynamic>.from(u as Map);
              final id = map['id'] as String? ?? '';
              return MatchedUser.fromJson({
                ...map,
                'isFavorite': favoriteIds.contains(id),
              });
            })
            .where((u) => currentUserId == null || u.id != currentUserId)
            .toList();

        setState(() {
          _isSearching = false;
          _searchResults = results;
          _searchErrorMessage = null;
        });
      } else {
        setState(() {
          _isSearching = false;
          _searchResults = [];
        });
      }
    } on DioException catch (e) {
      if (requestId != _activeRequestId || !mounted) return;
      final statusCode = e.response?.statusCode;
      String errorMsg = 'Failed to search users. Please try again.';
      if (statusCode == 429) {
        errorMsg = 'Too many searches, try again shortly';
      }
      setState(() {
        _isSearching = false;
        _searchResults = [];
        _searchErrorMessage = errorMsg;
      });
    } catch (_) {
      if (requestId != _activeRequestId || !mounted) return;
      setState(() {
        _isSearching = false;
        _searchResults = [];
        _searchErrorMessage = 'Failed to search users. Please try again.';
      });
    }
  }

  void _clearSearch() {
    _debounceTimer?.cancel();
    _activeRequestId++;
    _searchController.clear();
    setState(() {
      _isSearching = false;
      _searchResults = null;
      _searchErrorMessage = null;
    });
  }

  Future<void> _handleRefresh() async {
    AppLogger.click('Pull to Refresh Favorites', screen: 'FavoritesPage');
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
    });
    ref.invalidate(favoriteUsersProvider);
    await ref.read(favoriteUsersProvider.future).catchError((_) => <MatchedUser>[]);
    if (mounted) {
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    final favoriteUsersAsync = ref.watch(favoriteUsersProvider);
    final favoriteUsers = favoriteUsersAsync.value ?? const [];
    
    final bool showSkeleton = favoriteUsersAsync.isLoading && !favoriteUsersAsync.hasValue && _searchResults == null;

    if (showSkeleton) {
      return const FavoritesSkeleton();
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      key: const ValueKey('favorites_content'),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: Column(
          children: [
            Text(
              'Favorites',
              style: typography.titleCard.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Your saved partners',
              style: typography.bodySmall.copyWith(
                fontSize: 12,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Instagram-style Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: _searchErrorMessage != null 
                      ? const Color(0xFFEF4444) 
                      : colors.border.withValues(alpha: 0.6),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: colors.cardShadow.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: typography.bodyMedium.copyWith(color: colors.textPrimary),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search by @username...',
                  hintStyle: typography.bodySmall.copyWith(
                    color: colors.textSecondary.withValues(alpha: 0.6),
                    fontSize: 14,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: colors.primary,
                    size: 20,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close_rounded, size: 18, color: colors.textSecondary),
                          onPressed: _clearSearch,
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                ),
              ),
            ),
          ),

          // Main View Content (Search Results or Favorites List)
          Expanded(
            child: _buildBodyContent(favoriteUsers, colors, typography),
          ),
        ],
      ),
    );
  }

  Widget _buildBodyContent(List<MatchedUser> favoriteUsers, dynamic colors, dynamic typography) {
    // 1. Loading State
    if (_isSearching) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: CircularProgressIndicator(
            color: Color(0xFFFF4E64),
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    // 2. Rate Limit (429) or Network Error State
    if (_searchErrorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline_rounded, size: 48, color: Color(0xFFEF4444)),
              const SizedBox(height: 16),
              Text(
                _searchErrorMessage!,
                style: typography.bodyMedium.copyWith(
                  color: const Color(0xFFEF4444),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => _performSearch(_searchController.text.trim()),
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    // 3. Search Results Active State
    if (_searchResults != null) {
      if (_searchResults!.isNotEmpty) {
        return ListView.separated(
          padding: const EdgeInsets.only(left: 24, right: 24, top: 8, bottom: 100),
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: _searchResults!.length,
          separatorBuilder: (context, index) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final user = _searchResults![index];
            return FavoriteUserCard(user: user);
          },
        );
      }

      // No matching search results
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 48),
              Icon(
                Icons.person_search_rounded,
                size: 80,
                color: colors.textSecondary.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 20),
              Text(
                'No Users Found',
                style: typography.titleCard.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: colors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'No accounts found matching "${_searchController.text.trim()}"',
                style: typography.bodySmall.copyWith(
                  color: colors.textSecondary,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // 4. Default Favorites View
    return RefreshIndicator(
      onRefresh: _handleRefresh,
      color: const Color(0xFFFF4E64), // Pink/Red refresh color
      child: favoriteUsers.isNotEmpty
          ? ListView.separated(
              padding: const EdgeInsets.only(left: 24, right: 24, top: 8, bottom: 100),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: favoriteUsers.length,
              separatorBuilder: (context, index) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final user = favoriteUsers[index];
                return FavoriteUserCard(user: user);
              },
            )
          : SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 32),
                    const Center(
                      child: MatchingIllustration(
                        size: 180,
                        primaryColor: Color(0xFFFF4E64),
                        centerCircleColor: Color(0xFFFFF2F4),
                        icon: Icons.favorite,
                        iconColor: Color(0xFFFF4E64),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'No Favorites Yet',
                      style: typography.titleCard.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 19,
                        color: colors.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text(
                        'Start adding partners to your favorites and they will appear here!',
                        style: typography.bodySmall.copyWith(
                          color: colors.textSecondary,
                          fontSize: 13,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
    );
  }
}

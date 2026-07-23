import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dating_app/app/theme/app_spacing.dart';
import 'package:dating_app/app/theme/app_radius.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/features/home/presentation/widgets/matching_illustration.dart';
import 'package:dating_app/features/home/presentation/providers/matched_users_provider.dart';
import 'package:dating_app/features/home/presentation/widgets/favorite_user_card.dart';
import 'package:dating_app/features/home/presentation/widgets/favorites_skeleton.dart';

/// FavoritesPage renders the user's favorited telecallers.
class FavoritesPage extends ConsumerStatefulWidget {
  const FavoritesPage({super.key});

  @override
  ConsumerState<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends ConsumerState<FavoritesPage> {
  bool _isRefreshing = false;

  Future<void> _handleRefresh() async {
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
    
    final bool showSkeleton = favoriteUsersAsync.isLoading && !favoriteUsersAsync.hasValue;

    Widget content;
    if (showSkeleton) {
      content = const FavoritesSkeleton();
    } else {
      content = Scaffold(
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
              'Your saved telecallers',
              style: typography.bodySmall.copyWith(
                fontSize: 12,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        color: const Color(0xFFFF4E64), // Pink/Red refresh color
        child: favoriteUsers.isNotEmpty
            ? ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.space24),
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
                      const SizedBox(height: 80),
                      
                      // Centered concentric heart orbits radar illustration
                      const Center(
                        child: MatchingIllustration(
                          primaryColor: Color(0xFFFF4E64), // Pink/Red orbits
                          centerCircleColor: Color(0xFFFFF2F4), // Light pink background
                          icon: Icons.favorite, // Heart icon
                          iconColor: Color(0xFFFF4E64), // Pink/Red icon
                        ),
                      ),
                      const SizedBox(height: 48),

                      // Heading text
                      Text(
                        'No Favorites Yet',
                        style: typography.titleCard.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          color: colors.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),

                      // Helper Subtitle information
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text(
                          'Start adding telecallers to your favorites and they will appear here!',
                          style: typography.bodySmall.copyWith(
                            color: colors.textSecondary,
                            fontSize: 13,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      // const SizedBox(height: 32),
                      // // Light pink pull down action button
                      // GestureDetector(
                      //   onTap: _handleRefresh,
                      //   child: Container(
                      //     padding: const EdgeInsets.symmetric(
                      //       horizontal: 20,
                      //       vertical: 10,
                      //     ),
                      //     decoration: BoxDecoration(
                      //       color: const Color(0xFFFFF2F4), // light pink fill
                      //       borderRadius: AppRadius.pill,
                      //     ),
                      //     child: Row(
                      //       mainAxisSize: MainAxisSize.min,
                      //       children: const [
                      //         Icon(
                      //           Icons.refresh,
                      //           color: Color(0xFFFF4E64), // pink icon
                      //           size: 16,
                      //         ),
                      //         SizedBox(width: 8),
                      //         Text(
                      //           'Pull down to refresh',
                      //           style: TextStyle(
                      //             color: Color(0xFFFF4E64), // pink text
                      //             fontSize: 12,
                      //             fontWeight: FontWeight.bold,
                      //           ),
                      //         ),
                      //       ],
                      //     ),
                      //   ),
                      // ),
                      // const SizedBox(height: 80),
                    ],
                  ),
                ),
              ),
      ),
    );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: content,
    );
  }
}

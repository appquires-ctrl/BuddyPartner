import 'package:flutter/material.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/core/utils/app_logger.dart';

/// AppBottomNav provides a floating rounded card bottom navigation bar
/// so the custom wallpaper background is visible around and behind it.
/// Unified 4-tab layout: Home, Chat, Favorite, Setting.
class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool isFemale;
  final bool isTelecallerActive;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.isFemale = false,
    this.isTelecallerActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final navSelectedIndex = currentIndex.clamp(0, 3);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(left: 20.0, right: 20.0, bottom: 12.0, top: 4.0),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: colors.primary.withValues(alpha: 0.12),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: colors.primary.withValues(alpha: 0.10),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: NavigationBar(
              selectedIndex: navSelectedIndex,
              onDestinationSelected: (index) {
                final tabNames = ['Home', 'Chat', 'Favorite', 'Setting'];
                final tabName = index >= 0 && index < tabNames.length ? tabNames[index] : 'Tab $index';
                AppLogger.click('Bottom Nav Tab: $tabName');
                onTap(index);
              },
              backgroundColor: Colors.transparent,
              indicatorColor: colors.primary.withValues(alpha: 0.12),
              elevation: 0,
              height: 64,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.chat_bubble_outline),
                  selectedIcon: Icon(Icons.chat_bubble),
                  label: 'Chat',
                ),
                NavigationDestination(
                  icon: Icon(Icons.favorite_border),
                  selectedIcon: Icon(Icons.favorite),
                  label: 'Favorite',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: 'Setting',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

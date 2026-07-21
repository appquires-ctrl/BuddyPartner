import 'package:flutter/material.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';

/// AppBottomNav provides the bottom navigation bar for the app's shell.
/// Tracks Home, History, Wallet, and Profile tabs as seen in screenshots.
class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          top: BorderSide(color: colors.border, width: 1),
        ),
      ),
      child: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: onTap,
        backgroundColor: colors.surface,
        indicatorColor: colors.chipLavender,
        elevation: 0,
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.home_outlined, color: colors.textSecondary),
            selectedIcon: Icon(Icons.home, color: colors.primary),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_border, color: colors.textSecondary),
            selectedIcon: Icon(Icons.favorite, color: colors.primary),
            label: 'Favorite',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline, color: colors.textSecondary),
            selectedIcon: Icon(Icons.chat_bubble, color: colors.primary),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined, color: colors.textSecondary),
            selectedIcon: Icon(Icons.account_balance_wallet, color: colors.primary),
            label: 'Wallet',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined, color: colors.textSecondary),
            selectedIcon: Icon(Icons.settings, color: colors.primary),
            label: 'Setting',
          ),
        ],
      ),
    );
  }
}

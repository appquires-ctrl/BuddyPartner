import 'package:flutter/material.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';

/// AppBottomNav provides the bottom navigation bar for the app's shell.
/// Gender-aware: shows Withdraw tab for female telecallers, Wallet for males,
/// and omits earnings tab for non-telecaller female users.
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
    this.isTelecallerActive = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isNonTelecallerFemale = isFemale && !isTelecallerActive;

    final navSelectedIndex = isNonTelecallerFemale
        ? (currentIndex == 4 ? 3 : (currentIndex < 3 ? currentIndex : 0))
        : currentIndex;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          top: BorderSide(color: colors.border, width: 1),
        ),
      ),
      child: NavigationBar(
        selectedIndex: navSelectedIndex,
        onDestinationSelected: (selectedDestIndex) {
          if (isNonTelecallerFemale) {
            // Map 4-tab destination index back to 5-branch index
            if (selectedDestIndex == 3) {
              onTap(4); // Setting tab is branch index 4
            } else {
              onTap(selectedDestIndex);
            }
          } else {
            onTap(selectedDestIndex);
          }
        },
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
            icon: Icon(Icons.chat_bubble_outline, color: colors.textSecondary),
            selectedIcon: Icon(Icons.chat_bubble, color: colors.primary),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_border, color: colors.textSecondary),
            selectedIcon: Icon(Icons.favorite, color: colors.primary),
            label: 'Favorite',
          ),
          if (isFemale && isTelecallerActive)
            NavigationDestination(
              icon: Icon(Icons.local_florist_outlined, color: colors.textSecondary),
              selectedIcon: Icon(Icons.local_florist, color: colors.primary),
              label: 'Withdraw',
            )
          else if (!isFemale)
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

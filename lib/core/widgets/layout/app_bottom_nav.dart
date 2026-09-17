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
  final bool isSubscribed;
  final bool isTelecallerActive;
  final int unreadChatCount;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.isFemale = false,
    this.isSubscribed = false,
    this.isTelecallerActive = false,
    this.unreadChatCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final navSelectedIndex = currentIndex.clamp(0, 4);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 12.0, top: 4.0),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: isDark
                ? colors.surface.withValues(alpha: 0.94)
                : Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: isDark
                  ? colors.border.withValues(alpha: 0.3)
                  : colors.primary.withValues(alpha: 0.12),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.35)
                    : colors.primary.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: NavigationBarTheme(
              data: NavigationBarThemeData(
                indicatorColor: const Color(0xFF2563EB),
                indicatorShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((states) {
                  if (states.contains(WidgetState.selected)) {
                    return const IconThemeData(color: Colors.white, size: 22);
                  }
                  return IconThemeData(color: colors.textSecondary, size: 22);
                }),
                labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((states) {
                  if (states.contains(WidgetState.selected)) {
                    return const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2563EB),
                    );
                  }
                  return TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: colors.textSecondary,
                  );
                }),
              ),
              child: NavigationBar(
                selectedIndex: navSelectedIndex,
                onDestinationSelected: (index) {
                  final middleTab = isSubscribed ? (isFemale ? 'Withdraw' : 'Coins') : 'Plans';
                  final tabNames = ['Home', 'Chat', middleTab, 'Favorite', 'Setting'];
                  final tabName = index >= 0 && index < tabNames.length ? tabNames[index] : 'Tab $index';
                  AppLogger.click('Bottom Nav Tab: $tabName');
                  onTap(index);
                },
                backgroundColor: Colors.transparent,
                elevation: 0,
                height: 64,
                destinations: [
                  const NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home, color: Colors.white),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: unreadChatCount > 0
                        ? Badge.count(
                            count: unreadChatCount,
                            backgroundColor: const Color(0xFFEF4444),
                            textColor: Colors.white,
                            textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                            child: const Icon(Icons.chat_bubble_outline),
                          )
                        : const Icon(Icons.chat_bubble_outline),
                    selectedIcon: unreadChatCount > 0
                        ? Badge.count(
                            count: unreadChatCount,
                            backgroundColor: const Color(0xFFEF4444),
                            textColor: Colors.white,
                            textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                            child: const Icon(Icons.chat_bubble, color: Colors.white),
                          )
                        : const Icon(Icons.chat_bubble, color: Colors.white),
                    label: 'Chat',
                  ),
                  NavigationDestination(
                    icon: Icon(
                      isSubscribed
                          ? (isFemale ? Icons.account_balance_wallet_outlined : Icons.monetization_on_outlined)
                          : Icons.subscriptions_outlined,
                    ),
                    selectedIcon: Icon(
                      isSubscribed
                          ? (isFemale ? Icons.account_balance_wallet : Icons.currency_rupee)
                          : Icons.subscriptions,
                      color: Colors.white,
                    ),
                    label: isSubscribed
                        ? (isFemale ? 'Withdraw' : 'Wallet')
                        : 'Plans',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.favorite_border),
                    selectedIcon: Icon(Icons.favorite, color: Colors.white),
                    label: 'Favorite',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings, color: Colors.white),
                    label: 'Settings',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

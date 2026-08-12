import 'package:flutter/material.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/core/utils/app_logger.dart';

/// AppBottomNav provides the bottom navigation bar for the app's shell.
/// 3-tab layout: Home, Chat, Setting.
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
    final navSelectedIndex = currentIndex.clamp(0, 2);

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          top: BorderSide(color: colors.border, width: 1),
        ),
      ),
      child: NavigationBar(
        selectedIndex: navSelectedIndex,
        onDestinationSelected: (index) {
          final tabNames = ['Home', 'Chat', 'Setting'];
          final tabName = index >= 0 && index < tabNames.length ? tabNames[index] : 'Tab $index';
          AppLogger.click('Bottom Nav Tab: $tabName');
          onTap(index);
        },
        backgroundColor: colors.surface,
        indicatorColor: colors.chipLavender,
        elevation: 0,
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
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Setting',
          ),
        ],
      ),
    );
  }
}

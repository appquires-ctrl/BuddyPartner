import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/admin_colors.dart';
import '../providers/auth_provider.dart';
import '../providers/admin_providers.dart';

class AdminTopbar extends ConsumerWidget {
  final String? currentPath;

  const AdminTopbar({super.key, this.currentPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activePath = currentPath ?? GoRouterState.of(context).matchedLocation;
    final isUserManagement = activePath == '/users';

    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: AdminColors.surface,
        border: Border(
          bottom: BorderSide(color: AdminColors.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Search Bar (User Management Screen Only)
          if (isUserManagement)
            SizedBox(
              width: 320,
              height: 40,
              child: TextField(
                onChanged: (value) {
                  ref.read(usersProvider.notifier).setSearch(value);
                },
                decoration: InputDecoration(
                  hintText: 'Search users, phone, email...',
                  hintStyle: const TextStyle(fontSize: 13, color: AdminColors.textMuted),
                  prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AdminColors.textSecondary),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                  filled: true,
                  fillColor: AdminColors.surfaceMuted,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AdminColors.primary, width: 1.5),
                  ),
                ),
              ),
            ),

          const Spacer(),

          // System Status Indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AdminColors.successBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AdminColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Backend Online',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AdminColors.success,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),

          // Admin Profile Pill & Logout Menu
          PopupMenuButton<String>(
            offset: const Offset(0, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (value) {
              if (value == 'logout') {
                ref.read(authProvider.notifier).logout();
              }
            },
            itemBuilder: (context) => [
              // PopupMenuItem(
              //   value: 'profile',
              //   enabled: false,
              //   child: Row(
              //     children: const [
              //       Icon(Icons.admin_panel_settings_rounded, size: 18, color: AdminColors.primary),
              //       SizedBox(width: 10),
              //       Text(
              //         'Super Admin',
              //         style: TextStyle(fontWeight: FontWeight.bold, color: AdminColors.textPrimary),
              //       ),
              //     ],
              //   ),
              // ),
              // const PopupMenuDivider(),
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: const [
                    Icon(Icons.logout_rounded, size: 18, color: AdminColors.danger),
                    SizedBox(width: 10),
                    Text(
                      'Logout',
                      style: TextStyle(color: AdminColors.danger, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AdminColors.surfaceMuted,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AdminColors.border),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: AdminColors.primary,
                    child: const Text(
                      'A',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Admin',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AdminColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down_rounded, size: 18, color: AdminColors.textSecondary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

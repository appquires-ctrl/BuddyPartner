import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/admin_colors.dart';

class AdminSidebar extends StatelessWidget {
  final String currentPath;

  const AdminSidebar({
    super.key,
    required this.currentPath,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      decoration: const BoxDecoration(
        color: AdminColors.sidebarBackground,
        border: Border(
          right: BorderSide(color: AdminColors.border, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo & Branding Header
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                Image.asset(
                  'assets/images/app_logo.png',
                  width: 36,
                  height: 36,
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'BuddyPartner',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AdminColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Control Room',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AdminColors.primary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // Menu Items — Strictly limited to required 4 sections
          _buildNavItem(
            context,
            title: 'Dashboard',
            icon: Icons.dashboard_rounded,
            route: '/',
            isSelected: currentPath == '/',
          ),
          _buildNavItem(
            context,
            title: 'User Management',
            icon: Icons.people_alt_rounded,
            route: '/users',
            isSelected: currentPath == '/users',
          ),
          _buildNavItem(
            context,
            title: 'Withdrawal Requests',
            icon: Icons.account_balance_wallet_rounded,
            route: '/withdrawals',
            isSelected: currentPath == '/withdrawals',
          ),
          _buildNavItem(
            context,
            title: 'Reports Queue',
            icon: Icons.report_problem_rounded,
            route: '/reports',
            isSelected: currentPath == '/reports',
          ),
          _buildNavItem(
            context,
            title: 'Advertisements',
            icon: Icons.view_carousel_rounded,
            route: '/advertisements',
            isSelected: currentPath == '/advertisements',
          ),
          _buildNavItem(
            context,
            title: 'Buddy Banners',
            icon: Icons.celebration_rounded,
            route: '/buddy-banners',
            isSelected: currentPath == '/buddy-banners',
          ),
          _buildNavItem(
            context,
            title: 'App Version Gate',
            icon: Icons.system_update_rounded,
            route: '/app-config',
            isSelected: currentPath == '/app-config',
          ),
          _buildNavItem(
            context,
            title: 'Promo Codes',
            icon: Icons.local_offer_rounded,
            route: '/promo-codes',
            isSelected: currentPath == '/promo-codes',
          ),
          

          const Spacer(),

          // Version / Environment Tag
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AdminColors.surfaceMuted,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: const [
                  Icon(Icons.shield_outlined, size: 16, color: AdminColors.textSecondary),
                  SizedBox(width: 8),
                  Text(
                    'Admin Panel v1.0',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AdminColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required String title,
    required IconData icon,
    required String route,
    required bool isSelected,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            if (!isSelected) {
              context.go(route);
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? AdminColors.activePillBg : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected ? AdminColors.activePillText : AdminColors.textSecondary,
                ),
                const SizedBox(width: 14),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? AdminColors.activePillText : AdminColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

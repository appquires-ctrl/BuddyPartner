import 'package:flutter/material.dart';
import '../theme/admin_colors.dart';
import 'admin_sidebar.dart';
import 'admin_topbar.dart';

class AdminShell extends StatelessWidget {
  final String currentPath;
  final Widget child;

  const AdminShell({
    super.key,
    required this.currentPath,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminColors.background,
      body: Row(
        children: [
          // Sidebar
          AdminSidebar(currentPath: currentPath),

          // Main Layout Area
          Expanded(
            child: Column(
              children: [
                // Topbar
                AdminTopbar(currentPath: currentPath),

                // Scrollable Viewport Body
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(28.0),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

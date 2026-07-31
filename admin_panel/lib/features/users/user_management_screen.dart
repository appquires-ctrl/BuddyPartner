import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../theme/admin_colors.dart';
import '../../theme/admin_theme.dart';
import '../../providers/admin_providers.dart';

class UserManagementScreen extends ConsumerWidget {
  const UserManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersState = ref.watch(usersProvider);
    final usersNotifier = ref.read(usersProvider.notifier);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Screen Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'User Management',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AdminColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Search, inspect user profiles, and manage ban/unban moderation status',
                    style: TextStyle(
                      fontSize: 13,
                      color: AdminColors.textSecondary,
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => usersNotifier.fetchUsers(),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Refresh'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.surface,
                  foregroundColor: AdminColors.primary,
                  side: const BorderSide(color: AdminColors.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  elevation: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Filters Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AdminColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AdminColors.border),
            ),
            child: Row(
              children: [
                // Gender Filter Dropdown
                const Text('Gender: ', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AdminColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: usersState.gender,
                      style: const TextStyle(fontSize: 13, color: AdminColors.textPrimary),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All Genders')),
                        DropdownMenuItem(value: 'male', child: Text('Male')),
                        DropdownMenuItem(value: 'female', child: Text('Female')),
                      ],
                      onChanged: (val) {
                        if (val != null) usersNotifier.setGender(val);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 24),

                // Status Filter Dropdown
                const Text('Status: ', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AdminColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: usersState.isBanned,
                      style: const TextStyle(fontSize: 13, color: AdminColors.textPrimary),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All Statuses')),
                        DropdownMenuItem(value: 'false', child: Text('Active Only')),
                        DropdownMenuItem(value: 'true', child: Text('Banned Only')),
                      ],
                      onChanged: (val) {
                        if (val != null) usersNotifier.setIsBanned(val);
                      },
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  'Total Users: ${usersState.total}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AdminColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Users Full-Width Table Container
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AdminColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AdminColors.border),
            ),
            child: usersState.isLoading
                ? const SizedBox(
                    height: 300,
                    child: Center(child: CircularProgressIndicator(color: AdminColors.primary)),
                  )
                : usersState.users.isEmpty
                    ? Container(
                        padding: const EdgeInsets.all(48),
                        alignment: Alignment.center,
                        child: Column(
                          children: const [
                            Icon(Icons.person_search_rounded, size: 48, color: AdminColors.textMuted),
                            SizedBox(height: 12),
                            Text(
                              'No users match the criteria',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AdminColors.textSecondary),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final width = constraints.maxWidth > 950 ? constraints.maxWidth : 950.0;
                              return SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: width,
                                  child: Table(
                                    columnWidths: const {
                                      0: FlexColumnWidth(3.0), // USER
                                      1: FlexColumnWidth(1.8), // GENDER
                                      2: FlexColumnWidth(3.2), // PHONE / EMAIL
                                      3: FlexColumnWidth(2.2), // SIGNUP DATE
                                      4: FlexColumnWidth(2.0), // REPORTS
                                      5: FlexColumnWidth(2.0), // STATUS
                                      6: FlexColumnWidth(2.8), // ACTIONS
                                    },
                                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                                    children: [
                                      // Table Header
                                      TableRow(
                                        decoration: const BoxDecoration(
                                          color: AdminColors.surfaceMuted,
                                        ),
                                        children: [
                                          _buildHeaderCell('USER'),
                                          _buildHeaderCell('GENDER'),
                                          _buildHeaderCell('PHONE / EMAIL'),
                                          _buildHeaderCell('SIGNUP DATE'),
                                          _buildHeaderCell('REPORTS'),
                                          _buildHeaderCell('STATUS'),
                                          _buildHeaderCell('ACTIONS'),
                                        ],
                                      ),

                                      // Data Rows
                                      ...usersState.users.map((user) {
                                        final isBanned = user['is_banned'] == true;
                                        final name = user['name'] ?? 'Unknown User';
                                        final phone = user['phone'] ?? user['email'] ?? 'N/A';
                                        final gender = (user['gender'] ?? 'N/A').toString().toUpperCase();
                                        final signupDateStr = user['signup_date'] != null
                                            ? DateFormat('MMM dd, yyyy').format(DateTime.parse(user['signup_date']))
                                            : 'N/A';
                                        final reportCount = user['report_count'] ?? 0;

                                        return TableRow(
                                          decoration: const BoxDecoration(
                                            border: Border(bottom: BorderSide(color: AdminColors.border, width: 1)),
                                          ),
                                          children: [
                                            // USER
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  CircleAvatar(
                                                    radius: 15,
                                                    backgroundColor: AdminColors.activePillBg,
                                                    child: Text(
                                                      name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                                      style: const TextStyle(fontWeight: FontWeight.bold, color: AdminColors.primary, fontSize: 12),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Text(
                                                      name,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),

                                            // GENDER
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              child: Align(
                                                alignment: Alignment.centerLeft,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: gender == 'FEMALE' ? const Color(0xFFFCE7F3) : const Color(0xFFEFF6FF),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    gender,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                      color: gender == 'FEMALE' ? const Color(0xFFDB2777) : const Color(0xFF2563EB),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),

                                            // PHONE / EMAIL
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              child: Text(
                                                phone,
                                                style: AdminTheme.tabularNumeralStyle,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),

                                            // SIGNUP DATE
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              child: Text(
                                                signupDateStr,
                                                style: const TextStyle(fontSize: 13),
                                              ),
                                            ),

                                            // REPORTS
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              child: Align(
                                                alignment: Alignment.centerLeft,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: reportCount > 0 ? AdminColors.warningBg : AdminColors.surfaceMuted,
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    '$reportCount reports',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                      color: reportCount > 0 ? AdminColors.warning : AdminColors.textMuted,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),

                                            // STATUS
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              child: Align(
                                                alignment: Alignment.centerLeft,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: isBanned ? AdminColors.dangerBg : AdminColors.successBg,
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: Text(
                                                    isBanned ? 'BANNED' : 'ACTIVE',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                      color: isBanned ? AdminColors.danger : AdminColors.success,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),

                                            // ACTIONS
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  OutlinedButton(
                                                    onPressed: () => _showUserDetailDialog(context, ref, user['id']),
                                                    style: OutlinedButton.styleFrom(
                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                      side: const BorderSide(color: AdminColors.border),
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                                    ),
                                                    child: const Text('Detail', style: TextStyle(fontSize: 12)),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  ElevatedButton(
                                                    onPressed: () async {
                                                      final success = await usersNotifier.toggleBan(user['id'], isBanned);
                                                      if (context.mounted && success) {
                                                        ScaffoldMessenger.of(context).showSnackBar(
                                                          SnackBar(
                                                            content: Text(isBanned ? 'User unbanned' : 'User banned'),
                                                            backgroundColor: isBanned ? AdminColors.success : AdminColors.danger,
                                                          ),
                                                        );
                                                      }
                                                    },
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: isBanned ? AdminColors.success : AdminColors.danger,
                                                      foregroundColor: Colors.white,
                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                                      elevation: 0,
                                                    ),
                                                    child: Text(isBanned ? 'Unban' : 'Ban', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),

                          // Pagination Controls
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Page ${usersState.page} of ${usersState.totalPages}',
                                  style: const TextStyle(fontSize: 13, color: AdminColors.textSecondary),
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.chevron_left_rounded),
                                      onPressed: usersState.page > 1
                                          ? () => usersNotifier.setPage(usersState.page - 1)
                                          : null,
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.chevron_right_rounded),
                                      onPressed: usersState.page < usersState.totalPages
                                          ? () => usersNotifier.setPage(usersState.page + 1)
                                          : null,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AdminColors.textSecondary),
      ),
    );
  }

  void _showUserDetailDialog(BuildContext context, WidgetRef ref, String userId) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: 500,
            padding: const EdgeInsets.all(24),
            child: Consumer(
              builder: (context, ref, child) {
                final detailAsync = ref.watch(userDetailProvider(userId));
                return detailAsync.when(
                  data: (user) {
                    if (user == null) return const Text('User not found');
                    final reports = user['reports'] as List<dynamic>? ?? [];
                    final callStats = user['callStats'] as Map<String, dynamic>? ?? {};

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              user['name'] ?? 'User Details',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                        const Divider(),
                        const SizedBox(height: 12),
                        Text('Phone: ${user['phone'] ?? 'N/A'}', style: AdminTheme.tabularNumeralStyle),
                        Text('Gender: ${user['gender'] ?? 'N/A'}'),
                        Text('Status: ${user['is_banned'] == true ? 'BANNED' : 'ACTIVE'}'),
                        const SizedBox(height: 16),
                        const Text('Call Statistics:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('Total Calls: ${callStats['total_calls'] ?? 0}'),
                        Text('Total Call Duration: ${callStats['total_duration'] ?? 0}s'),
                        const SizedBox(height: 16),
                        const Text('Report History Against User:', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        reports.isEmpty
                            ? const Text('No reports filed against this user.', style: TextStyle(color: AdminColors.textMuted))
                            : Flexible(
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: reports.length,
                                  itemBuilder: (context, i) {
                                    final r = reports[i];
                                    return ListTile(
                                      dense: true,
                                      title: Text(r['reason'] ?? 'Report', style: const TextStyle(fontWeight: FontWeight.bold)),
                                      subtitle: Text('By: ${r['reporter_name'] ?? 'Anonymous'} • ${r['description'] ?? ''}'),
                                    );
                                  },
                                ),
                              ),
                      ],
                    );
                  },
                  loading: () => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
                  error: (e, s) => Text('Error loading user detail: $e'),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

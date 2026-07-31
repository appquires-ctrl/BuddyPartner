import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../theme/admin_colors.dart';
import '../../theme/admin_theme.dart';
import '../../providers/admin_providers.dart';

class ReportsQueueScreen extends ConsumerWidget {
  const ReportsQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsState = ref.watch(reportsProvider);
    final reportsNotifier = ref.read(reportsProvider.notifier);
    final usersNotifier = ref.read(usersProvider.notifier);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Reports Queue & Moderation Audit',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AdminColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Audit filed user reports and trigger manual bans for policy violations',
                    style: TextStyle(
                      fontSize: 13,
                      color: AdminColors.textSecondary,
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => reportsNotifier.fetchReports(),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Refresh Queue'),
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
          const SizedBox(height: 24),

          // Reports Table Container
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AdminColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AdminColors.border),
            ),
            child: reportsState.isLoading
                ? const SizedBox(
                    height: 300,
                    child: Center(child: CircularProgressIndicator(color: AdminColors.primary)),
                  )
                : reportsState.reports.isEmpty
                    ? Container(
                        padding: const EdgeInsets.all(48),
                        alignment: Alignment.center,
                        child: Column(
                          children: const [
                            Icon(Icons.check_circle_outline_rounded, size: 48, color: AdminColors.success),
                            SizedBox(height: 12),
                            Text(
                              'No reports filed yet',
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
                                      0: FlexColumnWidth(2.2), // DATE & TIME
                                      1: FlexColumnWidth(3.0), // REPORTER
                                      2: FlexColumnWidth(3.0), // REPORTED USER
                                      3: FlexColumnWidth(2.0), // REASON
                                      4: FlexColumnWidth(4.0), // DESCRIPTION
                                      5: FlexColumnWidth(2.2), // ACTION
                                    },
                                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                                    children: [
                                      // Table Header
                                      TableRow(
                                        decoration: const BoxDecoration(
                                          color: AdminColors.surfaceMuted,
                                        ),
                                        children: [
                                          _buildHeaderCell('DATE & TIME'),
                                          _buildHeaderCell('REPORTER'),
                                          _buildHeaderCell('REPORTED USER'),
                                          _buildHeaderCell('REASON'),
                                          _buildHeaderCell('DESCRIPTION'),
                                          _buildHeaderCell('ACTION'),
                                        ],
                                      ),

                                      // Data Rows
                                      ...reportsState.reports.map((report) {
                                        final reporterName = report['reporter_name'] ?? 'Anonymous';
                                        final reporterPhone = report['reporter_phone'] ?? '';
                                        final reportedName = report['reported_name'] ?? 'Unknown User';
                                        final reportedPhone = report['reported_phone'] ?? '';
                                        final isReportedBanned = report['reported_is_banned'] == true;
                                        final reason = report['reason'] ?? 'Inappropriate behavior';
                                        final description = report['description'] ?? 'No description provided';
                                        final dateStr = report['created_at'] != null
                                            ? DateFormat('MMM dd, hh:mm a').format(DateTime.parse(report['created_at']))
                                            : 'N/A';

                                        return TableRow(
                                          decoration: const BoxDecoration(
                                            border: Border(bottom: BorderSide(color: AdminColors.border, width: 1)),
                                          ),
                                          children: [
                                            // DATE & TIME
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              child: Text(dateStr, style: const TextStyle(fontSize: 13)),
                                            ),

                                            // REPORTER
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(reporterName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                                  Text(reporterPhone, style: AdminTheme.tabularNumeralStyle.copyWith(fontSize: 11, color: AdminColors.textSecondary)),
                                                ],
                                              ),
                                            ),

                                            // REPORTED USER
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Column(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(reportedName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                                      Text(reportedPhone, style: AdminTheme.tabularNumeralStyle.copyWith(fontSize: 11, color: AdminColors.textSecondary)),
                                                    ],
                                                  ),
                                                  const SizedBox(width: 8),
                                                  if (isReportedBanned)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: AdminColors.dangerBg,
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: const Text(
                                                        'BANNED',
                                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AdminColors.danger),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),

                                            // REASON
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              child: Align(
                                                alignment: Alignment.centerLeft,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: AdminColors.warningBg,
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    reason,
                                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AdminColors.warning),
                                                  ),
                                                ),
                                              ),
                                            ),

                                            // DESCRIPTION
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              child: Text(
                                                description,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary),
                                              ),
                                            ),

                                            // ACTION
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              child: ElevatedButton(
                                                onPressed: isReportedBanned
                                                    ? null
                                                    : () async {
                                                        final success = await usersNotifier.toggleBan(report['reported_user_id'], false);
                                                        if (context.mounted && success) {
                                                          reportsNotifier.fetchReports();
                                                          ScaffoldMessenger.of(context).showSnackBar(
                                                            const SnackBar(
                                                              content: Text('Reported user banned successfully'),
                                                              backgroundColor: AdminColors.danger,
                                                            ),
                                                          );
                                                        }
                                                      },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: AdminColors.danger,
                                                  foregroundColor: Colors.white,
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                                  elevation: 0,
                                                ),
                                                child: Text(
                                                  isReportedBanned ? 'Already Banned' : 'Ban User',
                                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                                ),
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
                                  'Page ${reportsState.page} of ${reportsState.totalPages}',
                                  style: const TextStyle(fontSize: 13, color: AdminColors.textSecondary),
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.chevron_left_rounded),
                                      onPressed: reportsState.page > 1
                                          ? () => reportsNotifier.setPage(reportsState.page - 1)
                                          : null,
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.chevron_right_rounded),
                                      onPressed: reportsState.page < reportsState.totalPages
                                          ? () => reportsNotifier.setPage(reportsState.page + 1)
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
}

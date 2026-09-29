import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../theme/admin_colors.dart';
import '../../../../providers/admin_providers.dart';

class BannedDevicesPage extends ConsumerStatefulWidget {
  const BannedDevicesPage({super.key});

  @override
  ConsumerState<BannedDevicesPage> createState() => _BannedDevicesPageState();
}

class _BannedDevicesPageState extends ConsumerState<BannedDevicesPage> {
  void _openBanDeviceDialog() {
    final deviceIdCtrl = TextEditingController();
    final reasonCtrl = TextEditingController(text: 'Suspicious device / abusive behavior');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.block_rounded, color: AdminColors.danger),
            SizedBox(width: 8),
            Text('Blacklist Device ID', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the device hardware identifier or device fingerprint to permanently restrict all current and future accounts on this phone.',
              style: TextStyle(fontSize: 13, color: AdminColors.textSecondary),
            ),
            const SizedBox(height: 16),
            const Text('Device ID / Hardware Hash', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              controller: deviceIdCtrl,
              decoration: InputDecoration(
                hintText: 'e.g. 8d39f7a1-5b23-4c91...',
                hintStyle: const TextStyle(fontSize: 12, color: AdminColors.textMuted),
                filled: true,
                fillColor: AdminColors.surfaceMuted,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Reason for Blacklisting', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              controller: reasonCtrl,
              decoration: InputDecoration(
                hintText: 'e.g. Chargeback fraud, harassment, burner abuse',
                hintStyle: const TextStyle(fontSize: 12, color: AdminColors.textMuted),
                filled: true,
                fillColor: AdminColors.surfaceMuted,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AdminColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final deviceId = deviceIdCtrl.text.trim();
              final reason = reasonCtrl.text.trim();
              if (deviceId.isEmpty) return;

              Navigator.pop(ctx);
              final success = await ref.read(bannedDevicesProvider.notifier).banDevice(deviceId, reason);
              if (mounted) {
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Device added to blacklist successfully. All associated accounts terminated.'),
                      backgroundColor: AdminColors.success,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Failed to ban device. Check logs.'),
                      backgroundColor: AdminColors.danger,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminColors.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Blacklist Device'),
          ),
        ],
      ),
    );
  }

  void _confirmUnban(String deviceId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove from Blacklist?'),
        content: Text('Are you sure you want to lift the hardware ban for device:\n\n$deviceId'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await ref.read(bannedDevicesProvider.notifier).unbanDevice(deviceId);
              if (mounted && success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Device removed from blacklist.'),
                    backgroundColor: AdminColors.success,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm Unban'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bannedDevicesProvider);
    final dateFormat = DateFormat('MMM dd, yyyy • hh:mm a');

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Hardware Device Blacklist',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AdminColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Permanent hardware device moderation to block malicious actors from evading account bans',
                    style: TextStyle(
                      fontSize: 13,
                      color: AdminColors.textSecondary,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () => ref.read(bannedDevicesProvider.notifier).fetchDevices(),
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
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _openBanDeviceDialog,
                    icon: const Icon(Icons.add_moderator_rounded, size: 18),
                    label: const Text('Blacklist Device'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminColors.danger,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Informational Tip Banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AdminColors.infoBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AdminColors.info.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: const [
                Icon(Icons.info_outline_rounded, color: AdminColors.info, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Fast O(1) hardware enforcement: Banned device IDs are cached globally across Redis cluster nodes. Any HTTP request or socket session matching a blacklisted device is immediately rejected.',
                    style: TextStyle(fontSize: 12, color: AdminColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Table Card
          Container(
            decoration: BoxDecoration(
              color: AdminColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AdminColors.border),
            ),
            child: state.isLoading
                ? const Padding(
                    padding: EdgeInsets.all(40.0),
                    child: Center(child: CircularProgressIndicator(color: AdminColors.primary)),
                  )
                : state.devices.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(40.0),
                        child: Center(
                          child: Text(
                            'No devices are currently blacklisted.',
                            style: TextStyle(color: AdminColors.textSecondary),
                          ),
                        ),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(AdminColors.surfaceMuted),
                          columns: const [
                            DataColumn(label: Text('Device Identifier', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Linked Accounts', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Reason', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Banned By', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Date Banned', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                          ],
                          rows: state.devices.map((d) {
                            final deviceId = d['device_id'] ?? '';
                            final reason = d['reason'] ?? '-';
                            final bannedBy = d['banned_by'] ?? 'admin';
                            final linkedCount = d['associated_users_count'] ?? 0;
                            final createdAtStr = d['created_at'];
                            DateTime? createdDate;
                            if (createdAtStr != null) {
                              createdDate = DateTime.tryParse(createdAtStr);
                            }

                            return DataRow(
                              cells: [
                                DataCell(
                                  Row(
                                    children: [
                                      const Icon(Icons.phonelink_erase_rounded, size: 16, color: AdminColors.danger),
                                      const SizedBox(width: 8),
                                      Text(
                                        deviceId.length > 24 ? '${deviceId.substring(0, 24)}...' : deviceId,
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                                      ),
                                    ],
                                  ),
                                ),
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: linkedCount > 0 ? AdminColors.dangerBg : AdminColors.surfaceMuted,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '$linkedCount user${linkedCount == 1 ? '' : 's'}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: linkedCount > 0 ? AdminColors.danger : AdminColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(Text(reason, style: const TextStyle(fontSize: 12))),
                                DataCell(Text(bannedBy, style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary))),
                                DataCell(
                                  Text(
                                    createdDate != null ? dateFormat.format(createdDate.toLocal()) : '-',
                                    style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary),
                                  ),
                                ),
                                DataCell(
                                  TextButton.icon(
                                    onPressed: () => _confirmUnban(deviceId),
                                    icon: const Icon(Icons.lock_open_rounded, size: 14, color: AdminColors.primary),
                                    label: const Text('Unban', style: TextStyle(fontSize: 12, color: AdminColors.primary)),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

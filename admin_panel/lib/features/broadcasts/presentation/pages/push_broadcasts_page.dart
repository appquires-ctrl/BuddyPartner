import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../theme/admin_colors.dart';
import '../../../../providers/admin_providers.dart';

class PushBroadcastsPage extends ConsumerStatefulWidget {
  const PushBroadcastsPage({super.key});

  @override
  ConsumerState<PushBroadcastsPage> createState() => _PushBroadcastsPageState();
}

class _PushBroadcastsPageState extends ConsumerState<PushBroadcastsPage> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _imageUrlController = TextEditingController();
  final _cityController = TextEditingController();

  String _targetSegment = 'all';
  String _targetGender = 'all';
  String _deepLink = '/subscribe';

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _imageUrlController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  void _confirmAndSend() {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();

    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter both Title and Notification Message.'),
          backgroundColor: AdminColors.danger,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.campaign_rounded, color: AdminColors.primary),
            SizedBox(width: 8),
            Text('Confirm Push Broadcast', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to dispatch this notification to:'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AdminColors.surfaceMuted,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• Segment: $_targetSegment', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('• Gender: $_targetGender'),
                  if (_cityController.text.trim().isNotEmpty)
                    Text('• City: ${_cityController.text.trim()}'),
                  Text('• Deep Link: $_deepLink'),
                  const Divider(),
                  Text('Title: $title', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('Body: $body'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '⚠️ This message will immediately ping registered user devices via Firebase Cloud Messaging.',
              style: TextStyle(fontSize: 12, color: AdminColors.textSecondary),
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
              Navigator.pop(ctx);
              final success = await ref.read(pushBroadcastsProvider.notifier).sendBroadcast(
                    title: title,
                    body: body,
                    imageUrl: _imageUrlController.text.trim().isNotEmpty
                        ? _imageUrlController.text.trim()
                        : null,
                    targetSegment: _targetSegment,
                    targetCity: _cityController.text.trim().isNotEmpty
                        ? _cityController.text.trim()
                        : null,
                    targetGender: _targetGender != 'all' ? _targetGender : null,
                    deepLink: _deepLink,
                  );

              if (mounted) {
                final state = ref.read(pushBroadcastsProvider);
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(state.successMessage ?? 'Broadcast sent successfully!'),
                      backgroundColor: AdminColors.success,
                    ),
                  );
                  _titleController.clear();
                  _bodyController.clear();
                  _imageUrlController.clear();
                  _cityController.clear();
                } else if (state.error != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: ${state.error}'),
                      backgroundColor: AdminColors.danger,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Confirm & Send'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pushBroadcastsProvider);
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
                    'Push Broadcast Center',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AdminColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Multi-cast push notification campaigns for VIP upselling, re-engagement & announcements',
                    style: TextStyle(
                      fontSize: 13,
                      color: AdminColors.textSecondary,
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => ref.read(pushBroadcastsProvider.notifier).fetchHistory(),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Refresh Logs'),
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

          // Composer Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AdminColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AdminColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AdminColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.send_rounded, color: AdminColors.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Compose Notification Campaign',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AdminColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Audience Targeting Selectors
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    // Target Segment
                    SizedBox(
                      width: 260,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Target Audience', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AdminColors.textSecondary)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            initialValue: _targetSegment,
                            decoration: _inputDecoration(),
                            items: const [
                              DropdownMenuItem(value: 'all', child: Text('All Registered Users')),
                              DropdownMenuItem(value: 'unsubscribed', child: Text('Unsubscribed (VIP Upsell)')),
                              DropdownMenuItem(value: 'inactive_48h', child: Text('Inactive > 48 Hours')),
                              DropdownMenuItem(value: 'active_today', child: Text('Active Today')),
                            ],
                            onChanged: (val) {
                              if (val != null) setState(() => _targetSegment = val);
                            },
                          ),
                        ],
                      ),
                    ),

                    // Target Gender
                    SizedBox(
                      width: 180,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Gender Filter', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AdminColors.textSecondary)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            initialValue: _targetGender,
                            decoration: _inputDecoration(),
                            items: const [
                              DropdownMenuItem(value: 'all', child: Text('All Genders')),
                              DropdownMenuItem(value: 'male', child: Text('Male Only')),
                              DropdownMenuItem(value: 'female', child: Text('Female Only')),
                            ],
                            onChanged: (val) {
                              if (val != null) setState(() => _targetGender = val);
                            },
                          ),
                        ],
                      ),
                    ),

                    // City Filter
                    SizedBox(
                      width: 220,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('City (Optional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AdminColors.textSecondary)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _cityController,
                            decoration: _inputDecoration(hintText: 'e.g. Delhi, Mumbai'),
                          ),
                        ],
                      ),
                    ),

                    // Deep Link
                    SizedBox(
                      width: 220,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Deep Link Action', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AdminColors.textSecondary)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            initialValue: _deepLink,
                            decoration: _inputDecoration(),
                            items: const [
                              DropdownMenuItem(value: '/subscribe', child: Text('Subscription / VIP')),
                              DropdownMenuItem(value: '/coins', child: Text('Coin Packs')),
                              DropdownMenuItem(value: '/home', child: Text('App Home')),
                              DropdownMenuItem(value: '/buddy', child: Text('Buddy Connect')),
                            ],
                            onChanged: (val) {
                              if (val != null) setState(() => _deepLink = val);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Title Input
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Notification Title', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AdminColors.textSecondary)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _titleController,
                      maxLength: 65,
                      decoration: _inputDecoration(hintText: 'e.g. Special Weekend Offer! Get Unlimited Calls 👑'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Body Input
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Notification Message', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AdminColors.textSecondary)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _bodyController,
                      maxLength: 180,
                      maxLines: 3,
                      decoration: _inputDecoration(hintText: 'Write compelling copy to engage users and drive opens...'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Image URL
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Banner Image URL (Optional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AdminColors.textSecondary)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _imageUrlController,
                      decoration: _inputDecoration(hintText: 'https://example.com/banner.jpg'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Send Button
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: state.isSending ? null : _confirmAndSend,
                    icon: state.isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.campaign_rounded, size: 20),
                    label: Text(state.isSending ? 'Dispatching Multicast...' : 'Send Broadcast Now'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Broadcast History Section
          const Text(
            'Past Broadcast Campaigns',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AdminColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),

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
                : state.broadcasts.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(40.0),
                        child: Center(
                          child: Text(
                            'No broadcast campaigns recorded yet.',
                            style: TextStyle(color: AdminColors.textSecondary),
                          ),
                        ),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(AdminColors.surfaceMuted),
                          columns: const [
                            DataColumn(label: Text('Campaign Title', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Segment', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Deep Link', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Recipients', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Delivered', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Dispatched At', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                          ],
                          rows: state.broadcasts.map((b) {
                            final title = b['title'] ?? '';
                            final body = b['body'] ?? '';
                            final segment = b['target_segment'] ?? 'all';
                            final deepLink = b['deep_link'] ?? '/home';
                            final recipients = b['recipient_count'] ?? 0;
                            final success = b['success_count'] ?? 0;
                            final createdAtStr = b['created_at'];
                            DateTime? createdDate;
                            if (createdAtStr != null) {
                              createdDate = DateTime.tryParse(createdAtStr);
                            }

                            return DataRow(
                              cells: [
                                DataCell(
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        title,
                                        style: const TextStyle(fontWeight: FontWeight.w600, color: AdminColors.textPrimary),
                                      ),
                                      Text(
                                        body,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 11, color: AdminColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AdminColors.activePillBg,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      segment,
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AdminColors.activePillText),
                                    ),
                                  ),
                                ),
                                DataCell(Text(deepLink, style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary))),
                                DataCell(Text('$recipients', style: const TextStyle(fontWeight: FontWeight.w600))),
                                DataCell(
                                  Text(
                                    '$success',
                                    style: const TextStyle(fontWeight: FontWeight.w600, color: AdminColors.success),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    createdDate != null ? dateFormat.format(createdDate.toLocal()) : '-',
                                    style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary),
                                  ),
                                ),
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AdminColors.successBg,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'Sent',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AdminColors.success),
                                    ),
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

  InputDecoration _inputDecoration({String? hintText}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(fontSize: 13, color: AdminColors.textMuted),
      filled: true,
      fillColor: AdminColors.surfaceMuted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AdminColors.primary, width: 1.5),
      ),
    );
  }
}

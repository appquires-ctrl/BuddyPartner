import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/app/theme/app_radius.dart';
import 'package:dating_app/app/theme/app_spacing.dart';
import 'package:dating_app/features/chat/data/chat_repository.dart';

/// ReportBlockDialog displays options to report a host and block them from the app.
class ReportBlockDialog extends ConsumerStatefulWidget {
  final String? reportedUserId;
  final String? conversationId;

  const ReportBlockDialog({super.key, this.reportedUserId, this.conversationId});

  @override
  ConsumerState<ReportBlockDialog> createState() => _ReportBlockDialogState();
}

class _ReportBlockDialogState extends ConsumerState<ReportBlockDialog> {
  String _selectedReason = 'Inappropriate behavior';
  final _descriptionController = TextEditingController();
  bool _isLoading = false;

  final List<String> _reasons = const [
    'Inappropriate behavior',
    'Abusive language',
    'Fake profile',
    'Asking for personal details / money',
    'Other'
  ];

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return AlertDialog(
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.lg,
      ),
      backgroundColor: colors.surface,
      title: Text(
        'Report & Block Host',
        style: typography.titleCard.copyWith(fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select a reason for reporting:',
              style: typography.bodySmall,
            ),
            const SizedBox(height: AppSpacing.space12),
            Column(
              children: _reasons.map((reason) {
                return RadioListTile<String>(
                  title: Text(reason, style: typography.bodyMedium),
                  value: reason,
                  groupValue: _selectedReason,
                  activeColor: colors.primary,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) {
                    setState(() {
                      _selectedReason = val ?? '';
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.space12),
            
            // Text field for description details
            Container(
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                borderRadius: AppRadius.md,
                border: Border.all(color: colors.border),
              ),
              child: TextField(
                controller: _descriptionController,
                maxLines: 2,
                style: typography.bodyMedium,
                decoration: InputDecoration(
                  hintText: 'Additional details (optional)',
                  hintStyle: typography.bodySmall,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(AppSpacing.space12),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => context.pop(),
          child: Text(
            'Cancel',
            style: TextStyle(color: colors.textSecondary),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.danger,
            foregroundColor: Colors.white,
            shape: const RoundedRectangleBorder(
              borderRadius: AppRadius.pill,
            ),
            elevation: 0,
          ),
          onPressed: _isLoading ? null : _submitReport,
          child: _isLoading 
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Report & Block'),
        ),
      ],
    );
  }

  Future<void> _submitReport() async {
    if (widget.reportedUserId == null) {
      context.pop();
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final repo = ref.read(chatRepositoryProvider);
      
      // Block user
      await repo.blockUser(widget.reportedUserId!);
      
      // Report user
      await repo.reportUser(
        reportedUserId: widget.reportedUserId!,
        reason: _selectedReason,
        description: _descriptionController.text.trim(),
        conversationId: widget.conversationId,
      );

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report submitted. User has been blocked.')),
        );
        // We should navigate away from the chat/call if we blocked them, 
        // but for simplicity we'll just pop to the previous screen.
        context.pop(); // Pop the chat/call screen too
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}

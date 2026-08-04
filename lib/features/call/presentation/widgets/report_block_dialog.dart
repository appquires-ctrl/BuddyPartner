import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dating_app/core/widgets/feedback/app_loading_indicator.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/core/utils/app_snack_bar.dart';
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
  String _selectedReason = 'Harassment or inappropriate behavior';
  final _descriptionController = TextEditingController();
  bool _isLoading = false;

  final List<String> _reasons = const [
    'Harassment or inappropriate behavior',
    'Fake profile or impersonation',
    'Spam or commercial advertising',
    'Inappropriate language or abusive behavior',
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
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.danger,
            side: BorderSide(color: colors.danger),
            shape: const RoundedRectangleBorder(
              borderRadius: AppRadius.pill,
            ),
          ),
          onPressed: _isLoading ? null : () => _handleAction(report: false),
          child: const Text('Block Only'),
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
          onPressed: _isLoading ? null : () => _handleAction(report: true),
          child: _isLoading 
              ? const AppLoadingIndicator(size: 16, color: Colors.white)
              : const Text('Report & Block'),
        ),
      ],
    );
  }

  Future<void> _handleAction({required bool report}) async {
    if (widget.reportedUserId == null) {
      context.pop();
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final repo = ref.read(chatRepositoryProvider);
      
      // Always block user
      await repo.blockUser(widget.reportedUserId!);
      
      // Report user if report is true
      if (report) {
        await repo.reportUser(
          reportedUserId: widget.reportedUserId!,
          reason: _selectedReason,
          description: _descriptionController.text.trim(),
          conversationId: widget.conversationId,
        );
      }

      if (mounted) {
        context.pop();
        AppSnackBar.showSuccess(
          context,
          report
              ? 'Report submitted. User has been blocked.'
              : 'User has been blocked.',
        );
        // Pop the chat/call screen as well to navigate back
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        AppSnackBar.showError(context, 'Error: $e');
      }
    }
  }
}

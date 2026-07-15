import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/app/theme/app_radius.dart';
import 'package:dating_app/app/theme/app_spacing.dart';

/// ReportBlockDialog displays options to report a host and block them from the app.
class ReportBlockDialog extends StatefulWidget {
  const ReportBlockDialog({super.key});

  @override
  State<ReportBlockDialog> createState() => _ReportBlockDialogState();
}

class _ReportBlockDialogState extends State<ReportBlockDialog> {
  String _selectedReason = 'Inappropriate behavior';
  final _descriptionController = TextEditingController();

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
          onPressed: () => context.pop(),
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
          onPressed: () {
            context.pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Report submitted. Host has been blocked.')),
            );
          },
          child: const Text('Report & Block'),
        ),
      ],
    );
  }
}

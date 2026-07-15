import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dating_app/app/router/route_names.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/app/theme/app_radius.dart';

/// LowBalanceDialog is an alert dialog shown when a user tries
/// to start a call with insufficient coins/rupees in their wallet balance.
class LowBalanceDialog extends StatelessWidget {
  const LowBalanceDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return AlertDialog(
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.lg,
      ),
      backgroundColor: colors.surface,
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: colors.danger, size: 28),
          const SizedBox(width: 8),
          Text(
            'Low Balance',
            style: typography.titleCard.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: Text(
        'Your wallet balance is insufficient to start this call (minimum ₹10 required). Please top up your wallet.',
        style: typography.bodyMedium,
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
            backgroundColor: colors.primary,
            foregroundColor: colors.surface,
            shape: const RoundedRectangleBorder(
              borderRadius: AppRadius.pill,
            ),
            elevation: 0,
          ),
          onPressed: () {
            context.pop();
            context.go(RouteNames.recharge);
          },
          child: const Text('Recharge'),
        ),
      ],
    );
  }
}

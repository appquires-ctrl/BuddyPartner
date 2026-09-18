import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';
import 'package:buddypartner/features/auth/application/auth_controller.dart';

/// Shows the professional, two-step Account Deletion bottom sheet.
Future<void> showDeleteAccountBottomSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const _DeleteAccountBottomSheet(),
  );
}

class _DeleteAccountBottomSheet extends ConsumerStatefulWidget {
  const _DeleteAccountBottomSheet();

  @override
  ConsumerState<_DeleteAccountBottomSheet> createState() =>
      _DeleteAccountBottomSheetState();
}

class _DeleteAccountBottomSheetState
    extends ConsumerState<_DeleteAccountBottomSheet> {
  int _currentStep = 0; // 0 = Reason selection, 1 = Final confirmation
  String? _selectedReason;
  final TextEditingController _feedbackController = TextEditingController();
  bool _isSubmitting = false;

  final List<({String key, String title, IconData icon})> _reasons = const [
    (
      key: 'found_match',
      title: 'I found someone / Met a match',
      icon: Icons.favorite_rounded,
    ),
    (
      key: 'privacy_safety',
      title: 'Privacy or safety concern',
      icon: Icons.shield_outlined,
    ),
    (
      key: 'coins_subscription',
      title: 'Issues with coins or subscription',
      icon: Icons.currency_rupee_rounded,
    ),
    (
      key: 'taking_break',
      title: 'Taking a break / removing the app',
      icon: Icons.pause_circle_outline_rounded,
    ),
    (
      key: 'not_enough_matches',
      title: 'Not getting enough matches',
      icon: Icons.people_outline_rounded,
    ),
    (key: 'other', title: 'Other reason', icon: Icons.edit_note_rounded),
  ];

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _handleDeleteAccount() async {
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();

    final reason = _selectedReason ?? 'other';
    final feedback = _feedbackController.text.trim();

    final success = await ref
        .read(authControllerProvider.notifier)
        .deleteAccount(
          reason: reason,
          feedback: feedback.isNotEmpty ? feedback : null,
        );

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      if (success) {
        AppSnackBar.showSuccess(
          context,
          'Your account and associated data have been permanently deleted.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1929) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _currentStep == 0
                  ? _buildReasonStep(colors)
                  : _buildConfirmationStep(colors),
            ),
          ),
        ),
      ),
    );
  }

  // ── Step 1: Reason Selector ────────────────────────────────────────────────
  Widget _buildReasonStep(dynamic colors) {
    final typography = context.typography;

    return SingleChildScrollView(
      key: const ValueKey('step_reason'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.border.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Title & Subtitle
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFDC2626),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Delete Account',
                      style: typography.titleCard.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Step 1 of 2 • Reason for leaving',
                      style: typography.bodySmall.copyWith(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'We\'re sad to see you go. Please let us know why you\'d like to delete your account:',
            style: typography.bodySmall.copyWith(
              color: colors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),

          // Reasons List
          ..._reasons.map((r) {
            final isSelected = _selectedReason == r.key;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedReason = r.key);
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colors.primary.withValues(alpha: 0.08)
                        : colors.surfaceMuted,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected
                          ? colors.primary
                          : colors.border.withValues(alpha: 0.6),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        r.icon,
                        size: 20,
                        color: isSelected
                            ? colors.primary
                            : colors.textSecondary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          r.title,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isSelected
                                ? colors.primary
                                : colors.textPrimary,
                          ),
                        ),
                      ),
                      if (isSelected)
                        Icon(
                          Icons.check_circle_rounded,
                          size: 18,
                          color: colors.primary,
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),

          // Optional Feedback Text Input
          if (_selectedReason != null) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _feedbackController,
              maxLines: 2,
              style: TextStyle(fontSize: 13.5, color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Additional feedback or details (optional)...',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: colors.textSecondary.withValues(alpha: 0.6),
                ),
                filled: true,
                fillColor: colors.surfaceMuted,
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: colors.border.withValues(alpha: 0.6),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.primary, width: 1.5),
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Action buttons (Cancel & Continue)
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    side: BorderSide(color: colors.border),
                  ),
                  onPressed: () =>
                      Navigator.of(context, rootNavigator: true).pop(),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _selectedReason != null
                        ? const Color(0xFFDC2626)
                        : colors.border,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _selectedReason != null
                      ? () {
                          HapticFeedback.lightImpact();
                          setState(() => _currentStep = 1);
                        }
                      : null,
                  child: const Text(
                    'Continue',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Step 2: Confirmation Step ──────────────────────────────────────────────
  Widget _buildConfirmationStep(dynamic colors) {
    final typography = context.typography;

    return SingleChildScrollView(
      key: const ValueKey('step_confirm'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.border.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Danger Warning Icon with pulse glow
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFDC2626).withValues(alpha: 0.2),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFDC2626),
              size: 36,
            ),
          ),
          const SizedBox(height: 18),

          // Heading
          Text(
            'Permanent Deletion Warning',
            style: typography.titleCard.copyWith(
              fontWeight: FontWeight.w900,
              fontSize: 20,
              color: const Color(0xFFDC2626),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'This action is irreversible. All of the following will be wiped permanently:',
            textAlign: TextAlign.center,
            style: typography.bodySmall.copyWith(
              color: colors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),

          // Bulleted Consequences List
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFFCA5A5).withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              children: [
                _buildConsequenceRow(
                  icon: Icons.person_remove_rounded,
                  title: 'Profile & Photos',
                  subtitle:
                      'Your profile, photos, and match history will be removed.',
                ),
                const SizedBox(height: 10),
                _buildConsequenceRow(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'Chats & Messages',
                  subtitle:
                      'All active conversations will be wiped immediately.',
                ),
                const SizedBox(height: 10),
                _buildConsequenceRow(
                  icon: Icons.currency_rupee_rounded,
                  title: 'Coins & Subscription',
                  subtitle:
                      'Remaining wallet coins and active passes are forfeited.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    side: BorderSide(color: colors.border),
                  ),
                  onPressed: _isSubmitting
                      ? null
                      : () => setState(() => _currentStep = 0),
                  child: Text(
                    'Back',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _isSubmitting ? null : _handleDeleteAccount,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Delete Account',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConsequenceRow({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFFDC2626)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF991B1B),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFFB91C1C),
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dating_app/app/router/route_names.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/app/theme/app_spacing.dart';
import 'package:dating_app/app/theme/app_radius.dart';
import 'package:dating_app/core/widgets/cards/app_card.dart';
import 'package:dating_app/core/widgets/buttons/app_primary_button.dart';
import 'package:dating_app/features/call/application/call_summary_provider.dart';
import 'package:dating_app/features/auth/application/auth_state_provider.dart';

/// CallSummaryPage displays the final call duration and cost summaries,
/// prompting users to provide ratings and optional text reviews.
class CallSummaryPage extends ConsumerStatefulWidget {
  const CallSummaryPage({super.key});

  @override
  ConsumerState<CallSummaryPage> createState() => _CallSummaryPageState();
}

class _CallSummaryPageState extends ConsumerState<CallSummaryPage> {
  int _selectedStars = 5;
  final _reviewController = TextEditingController();

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '0s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0) {
      return '${m}m ${s}s';
    }
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    
    final summary = ref.watch(lastCallSummaryProvider);
    final String matchedName = summary?.matchedUserName ?? 'User';
    final String matchedInitials = getInitials(matchedName);
    final String durationText = _formatDuration(summary?.durationSeconds ?? 0);
    final int cost = summary?.totalCost ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Call Ended'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.space24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: AppSpacing.space20),
              
              // Summary stats card block
              AppCard(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: const Color(0xFFE5DFFF),
                      child: Text(
                        matchedInitials,
                        style: const TextStyle(
                          color: Color(0xFF6B4EFF),
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space16),
                    Text(
                      matchedName,
                      style: typography.titleCard.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: AppSpacing.space4),
                    Text(
                      '₹10/min',
                      style: typography.bodySmall,
                    ),
                    const Divider(height: AppSpacing.space32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            Text(
                              'Duration',
                              style: typography.bodySmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              durationText,
                              style: typography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Column(
                          children: [
                            Text(
                              'Total Cost',
                              style: typography.bodySmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '₹$cost',
                              style: typography.bodyMedium.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colors.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.space32),

              // Rating panel selectors
              Text(
                'Rate your conversation',
                style: typography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppSpacing.space12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return IconButton(
                    icon: Icon(
                      index < _selectedStars ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 32,
                    ),
                    onPressed: () {
                      setState(() {
                        _selectedStars = index + 1;
                      });
                    },
                  );
                }),
              ),
              const SizedBox(height: AppSpacing.space24),

              // Review feedback block
              Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: AppRadius.md,
                  border: Border.all(color: colors.border),
                ),
                child: TextField(
                  controller: _reviewController,
                  maxLines: 3,
                  style: typography.bodyMedium,
                  decoration: InputDecoration(
                    hintText: 'Describe your experience (optional)',
                    hintStyle: typography.bodySmall,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(AppSpacing.space16),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.space32),

              // Actions
              AppPrimaryButton(
                text: 'Submit Review',
                onPressed: () {
                  context.go(RouteNames.home);
                },
              ),
              const SizedBox(height: AppSpacing.space12),
              
              TextButton(
                onPressed: () => context.go(RouteNames.home),
                child: Text(
                  'Back to Home',
                  style: typography.labelPill.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

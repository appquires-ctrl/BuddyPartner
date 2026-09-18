import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';
import 'package:buddypartner/core/widgets/coins/app_coin_icon.dart';
import 'package:buddypartner/core/widgets/feedback/app_loading_indicator.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';
import 'package:buddypartner/features/buddy/application/buddy_controller.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/features/buddy/domain/buddy_models.dart';

/// Bottom sheet to view and accept live open Buddy Requests in the user's city.
class OpenBuddyRequestsSheet extends ConsumerStatefulWidget {
  const OpenBuddyRequestsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const OpenBuddyRequestsSheet(),
    );
  }

  @override
  ConsumerState<OpenBuddyRequestsSheet> createState() => _OpenBuddyRequestsSheetState();
}

class _OpenBuddyRequestsSheetState extends ConsumerState<OpenBuddyRequestsSheet> {
  BuddyType? _selectedFilterType;
  String? _acceptingRequestId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final city = ref.read(authStateProvider).value?.city;
      ref.read(buddyControllerProvider.notifier).fetchOpenRequests(city: city);
    });
  }

  Future<void> _handleAccept(BuddyRequest request) async {
    if (_acceptingRequestId != null) return;
    setState(() => _acceptingRequestId = request.id);

    try {
      final acceptedReq = await ref.read(buddyControllerProvider.notifier).acceptBuddyRequest(request.id);

      if (!mounted) return;
      Navigator.of(context).pop(); // Close open requests list

      AppSnackBar.showSuccess(
        context,
        'Request accepted! Chat is now unlocked. Meet up in person and enter their OTP to claim reward!',
      );

      // Navigate directly to chat
      final convId = acceptedReq.conversationId ?? request.conversationId;
      final initiatorInfo = acceptedReq.initiator ?? request.initiator;
      final initiatorName = (initiatorInfo?.fullName != null && initiatorInfo!.fullName.isNotEmpty && initiatorInfo.fullName != 'User')
          ? initiatorInfo.fullName
          : ((request.initiator?.fullName.isNotEmpty ?? false) ? request.initiator!.fullName : 'Buddy Partner');

      if (convId != null && convId.isNotEmpty) {
        context.push(
          RouteNames.chat,
          extra: {
            'conversationId': convId,
            'userId': initiatorInfo?.id ?? request.initiatorId,
            'userName': initiatorName,
            'avatarSeed': initiatorInfo?.avatarSeed ?? request.initiator?.avatarSeed,
            'avatarStyle': initiatorInfo?.avatarStyle ?? request.initiator?.avatarStyle,
            'gender': initiatorInfo?.gender ?? request.initiator?.gender,
          },
        );
      }
    } catch (e) {
      if (mounted) {
        final err = e.toString().replaceAll('Exception: ', '');
        AppSnackBar.showError(context, err);
      }
    } finally {
      if (mounted) {
        setState(() => _acceptingRequestId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final buddyState = ref.watch(buddyControllerProvider);
    final userCity = ref.watch(authStateProvider).value?.city ?? 'your area';

    final filteredRequests = _selectedFilterType == null
        ? buddyState.openRequests
        : buddyState.openRequests.where((r) => r.buddyType == _selectedFilterType).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 28,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
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
          const SizedBox(height: 16),

          // Title & city
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Live Buddy Requests',
                      style: typography.titleCard.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Happening now in $userCity',
                      style: typography.bodySmall.copyWith(
                        color: colors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.close, color: colors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Filter bar
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _buildFilterChip('All Activities', isSelected: _selectedFilterType == null, onTap: () {
                  setState(() => _selectedFilterType = null);
                }),
                ...BuddyType.values.map((type) {
                  return _buildFilterChip(
                    type.title,
                    isSelected: _selectedFilterType == type,
                    onTap: () {
                      setState(() => _selectedFilterType = type);
                    },
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Request List
          Expanded(
            child: buddyState.isLoading && filteredRequests.isEmpty
                ? const Center(child: AppLoadingIndicator(size: 28))
                : (filteredRequests.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: colors.surfaceMuted,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.people_outline_rounded,
                                size: 48,
                                color: colors.textSecondary.withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No open requests in $userCity',
                              style: typography.titleCard.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 32.0),
                              child: Text(
                                'Tap any sticker on the home screen to start your own activity broadcast!',
                                style: typography.bodySmall.copyWith(
                                  color: colors.textSecondary,
                                  fontSize: 12.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          final city = ref.read(authStateProvider).value?.city;
                          await ref.read(buddyControllerProvider.notifier).fetchOpenRequests(city: city);
                        },
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                          itemCount: filteredRequests.length,
                          separatorBuilder: (_, index) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final req = filteredRequests[index];
                            final type = req.buddyType;
                            final isAccepting = _acceptingRequestId == req.id;

                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: colors.surfaceMuted,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: type.accentColor.withValues(alpha: 0.25),
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: type.accentColor.withValues(alpha: 0.06),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  // Sticker badge
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Container(
                                      width: 58,
                                      height: 58,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: type.gradientColors,
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                      ),
                                      child: Image.asset(
                                        type.stickerAsset,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, error, stack) => const Icon(
                                          Icons.local_activity_rounded,
                                          color: Colors.white,
                                          size: 26,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Details
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              type.title,
                                              style: typography.bodyMedium.copyWith(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                                color: colors.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFECFDF5),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: const Color(0xFFA7F3D0)),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const AppCoinIcon(size: 12),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    '+${req.accepterCoinReward}',
                                                    style: const TextStyle(
                                                      fontSize: 10.5,
                                                      fontWeight: FontWeight.bold,
                                                      color: Color(0xFF065F46),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          'By ${req.initiator?.fullName ?? "A buddy"} • ${req.city}',
                                          style: typography.bodySmall.copyWith(
                                            fontSize: 12,
                                            color: colors.textSecondary,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Accept Button
                                  SizedBox(
                                    height: 40,
                                    child: ElevatedButton(
                                      onPressed: isAccepting ? null : () => _handleAccept(req),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: type.accentColor,
                                        padding: const EdgeInsets.symmetric(horizontal: 14),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        elevation: 1,
                                      ),
                                      child: isAccepting
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Text(
                                              'Accept',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      )),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, {required bool isSelected, required VoidCallback onTap}) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? colors.primary : colors.surfaceMuted,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? colors.primary : colors.cardBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? Colors.white : colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

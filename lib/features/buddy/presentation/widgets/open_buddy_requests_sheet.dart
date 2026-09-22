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
import 'package:buddypartner/features/buddy/data/buddy_group_service.dart';
import 'package:buddypartner/features/buddy/presentation/widgets/create_buddy_request_sheet.dart';
import 'package:buddypartner/features/subscription/application/subscription_providers.dart';

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
  List<BuddyGroup> _openGroups = [];
  String? _selectedCity;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userCity = ref.read(authStateProvider).value?.city;
      _selectedCity = (userCity != null && userCity.isNotEmpty) ? userCity : 'All Cities';
      _refreshData();
    });
  }

  void _openCityPicker() {
    CityPickerSheet.show(context, currentCity: _selectedCity ?? 'All Cities').then((chosen) {
      if (chosen != null && chosen.isNotEmpty) {
        setState(() {
          _selectedCity = chosen;
        });
        _refreshData();
      }
    });
  }

  Future<void> _refreshData() async {
    final queryCity = (_selectedCity == 'All Cities' || _selectedCity == 'All') ? null : _selectedCity;
    await Future.wait([
      ref.read(buddyControllerProvider.notifier).fetchOpenRequests(city: queryCity),
      _fetchOpenGroups(queryCity),
    ]);
  }

  Future<void> _fetchOpenGroups(String? city) async {
    try {
      final groups = await ref.read(buddyGroupServiceProvider).listOpenGroups(city: city);
      if (mounted) {
        setState(() => _openGroups = groups);
      }
    } catch (_) {}
  }

  Future<void> _handleAccept(BuddyRequest request) async {
    final isSub = ref.read(subscriptionStatusProvider).value?.isSubscribed ?? false;
    if (!isSub) {
      Navigator.of(context).pop();
      context.push(RouteNames.subscribe);
      return;
    }

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

  Future<void> _handleJoinGroup(BuddyGroup group) async {
    if (_acceptingRequestId != null) return;
    setState(() => _acceptingRequestId = group.id);

    try {
      final joined = await ref.read(buddyGroupServiceProvider).joinGroup(group.id);

      if (!mounted) return;
      Navigator.of(context).pop();

      AppSnackBar.showSuccess(
        context,
        'Joined ${joined.title}! Start chatting in the group.',
      );

      ref.invalidate(myBuddyGroupsProvider);

      context.push(
        RouteNames.buddyGroupChat,
        extra: {
          'groupId': joined.id,
          'title': joined.title,
          'memberCount': joined.memberCount,
        },
      );
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

    final currentUserId = ref.watch(authStateProvider).value?.id;

    final filteredRequests = _selectedFilterType == null
        ? buddyState.openRequests.where((r) => r.buddyType != BuddyType.garba).toList()
        : buddyState.openRequests.where((r) => r.buddyType == _selectedFilterType && r.buddyType != BuddyType.garba).toList();

    final showGroups = (_selectedFilterType == null || _selectedFilterType == BuddyType.garba);
    final displayedGroups = showGroups
        ? _openGroups.where((g) {
            final isHost = currentUserId != null && g.initiatorId == currentUserId;
            return !isHost && !g.isMember;
          }).toList()
        : <BuddyGroup>[];
    final totalCount = displayedGroups.length + filteredRequests.length;

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
                    const SizedBox(height: 3),
                    InkWell(
                      onTap: _openCityPicker,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              (_selectedCity == 'All Cities' || _selectedCity == 'All')
                                  ? Icons.public_rounded
                                  : Icons.location_on_rounded,
                              size: 14,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _selectedCity ?? 'All Cities',
                              style: typography.bodySmall.copyWith(
                                color: colors.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(Icons.arrow_drop_down_rounded, size: 18, color: colors.primary),
                            const SizedBox(width: 4),
                            Text(
                              '(Tap to change)',
                              style: typography.bodySmall.copyWith(
                                color: colors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
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
            child: buddyState.isLoading && totalCount == 0
                ? const Center(child: AppLoadingIndicator(size: 28))
                : (totalCount == 0
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
                            if (_selectedCity != 'All Cities') ...[
                              const SizedBox(height: 14),
                              OutlinedButton.icon(
                                onPressed: () {
                                  setState(() => _selectedCity = 'All Cities');
                                  _refreshData();
                                },
                                icon: const Icon(Icons.public_rounded, size: 16),
                                label: const Text('View All Cities'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: colors.primary,
                                  side: BorderSide(color: colors.primary),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _refreshData,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                          itemCount: totalCount,
                          separatorBuilder: (_, index) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            if (index < displayedGroups.length) {
                              return _buildGroupCard(displayedGroups[index]);
                            }
                            final req = filteredRequests[index - displayedGroups.length];
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
                                              req.displayTitle,
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

  Widget _buildGroupCard(BuddyGroup group) {
    final colors = context.colors;
    final typography = context.typography;
    final currentUserId = ref.watch(authStateProvider).value?.id;
    final isAccepting = _acceptingRequestId == group.id;
    final isMemberOrHost = group.isMember || (currentUserId != null && group.initiatorId == currentUserId);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF9333EA).withValues(alpha: 0.35),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF9333EA).withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 58,
              height: 58,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF6B21A8), Color(0xFF9333EA)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Image.asset(
                'assets/images/garba_buddy.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.groups_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        group.title,
                        style: typography.bodyMedium.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF9333EA), Color(0xFF6B21A8)],
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${group.memberCount}/${group.maxMembers} Joined',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Host: ${group.hostName ?? "Garba Host"} • ${(group.city.toLowerCase() == "all" || group.city.toLowerCase() == "all cities") ? "All Cities" : group.city} • Free Join (0 OTP)',
                  style: typography.bodySmall.copyWith(
                    fontSize: 12,
                    color: const Color(0xFF10B981),
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 40,
            child: ElevatedButton(
              onPressed: isAccepting
                  ? null
                  : isMemberOrHost
                      ? () {
                          Navigator.of(context).pop();
                          context.push(
                            RouteNames.buddyGroupChat,
                            extra: {
                              'groupId': group.id,
                              'title': group.title,
                              'memberCount': group.memberCount,
                            },
                          );
                        }
                      : () => _handleJoinGroup(group),
              style: ElevatedButton.styleFrom(
                backgroundColor: isMemberOrHost ? const Color(0xFF10B981) : const Color(0xFF9333EA),
                foregroundColor: Colors.white,
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
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      isMemberOrHost ? 'Open Chat' : 'Join Group',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
            ),
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

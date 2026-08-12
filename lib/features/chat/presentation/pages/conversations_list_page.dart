import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/app/theme/app_spacing.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/features/chat/application/conversations_provider.dart';
import 'package:buddypartner/features/chat/application/presence_provider.dart';
import 'package:buddypartner/features/chat/domain/conversation.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';
import 'package:buddypartner/core/widgets/gradient_avatar.dart';
import 'package:buddypartner/core/widgets/shimmer/skeletons/conversation_list_item_skeleton.dart';
import 'package:buddypartner/features/home/presentation/widgets/matching_illustration.dart';
import 'package:buddypartner/core/utils/app_throttler.dart';

/// ConversationsListPage displays the user's active conversations
/// styled identically to the Favorites screen design system.
class ConversationsListPage extends ConsumerStatefulWidget {
  const ConversationsListPage({super.key});

  @override
  ConsumerState<ConversationsListPage> createState() => _ConversationsListPageState();
}

class _ConversationsListPageState extends ConsumerState<ConversationsListPage> {
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    // Auto-fetch fresh conversations on screen entry
    Future.microtask(() => ref.invalidate(conversationsProvider));
  }

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
    });
    ref.invalidate(conversationsProvider);
    await ref.read(conversationsProvider.future).catchError((_) => <Conversation>[]);
    if (mounted) {
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final conversationsAsync = ref.watch(conversationsProvider);

    final conversations = conversationsAsync.value ?? const [];
    final bool showSkeleton = conversationsAsync.isLoading && !conversationsAsync.hasValue;

    if (conversations.isNotEmpty) {
      final userIds = conversations.map((c) => c.otherUserId).toList();
      Future.microtask(() {
        ref.read(presenceProvider.notifier).fetchPresence(userIds);
      });
    }

    Widget content;
    if (showSkeleton) {
      content = Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          centerTitle: true,
          title: Column(
            children: [
              Text(
                'Messages',
                style: typography.titleCard.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Your conversations',
                style: typography.bodySmall.copyWith(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        body: ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.space24),
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 5,
          separatorBuilder: (context, index) => const SizedBox(height: 16),
          itemBuilder: (context, index) => const ConversationListItemSkeleton(),
        ),
      );
    } else {
      content = Scaffold(
        key: const ValueKey('conversations_content'),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          centerTitle: true,
          title: Column(
            children: [
              Text(
                'Messages',
                style: typography.titleCard.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Your conversations',
                style: typography.bodySmall.copyWith(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        body: RefreshIndicator(
          onRefresh: _handleRefresh,
          color: colors.primary,
          child: conversations.isNotEmpty
              ? ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.space24),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: conversations.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final conv = conversations[index];
                    return _ConversationCard(
                      key: ValueKey(conv.id),
                      conversation: conv,
                    );
                  },
                )
              : SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 80),
                        
                        // Centered concentric orbits radar illustration matching Favorites empty state
                        Center(
                          child: MatchingIllustration(
                            primaryColor: colors.primary,
                            centerCircleColor: colors.primary.withValues(alpha: 0.1),
                            icon: Icons.chat,
                            iconColor: colors.primary,
                          ),
                        ),
                        const SizedBox(height: 48),

                        // Heading text
                        Text(
                          'No Messages Yet',
                          style: typography.titleCard.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                            color: colors.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),

                        // Subtitle information
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Text(
                            'Start a conversation with a partner to see your chats here!',
                            style: typography.bodySmall.copyWith(
                              color: colors.textSecondary,
                              fontSize: 13,
                              height: 1.4,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        // const SizedBox(height: 32),

                        // // Pull down action button
                        // GestureDetector(
                        //   onTap: _handleRefresh,
                        //   child: Container(
                        //     padding: const EdgeInsets.symmetric(
                        //       horizontal: 20,
                        //       vertical: 10,
                        //     ),
                        //     decoration: BoxDecoration(
                        //       color: colors.primary.withValues(alpha: 0.1),
                        //       borderRadius: AppRadius.pill,
                        //     ),
                        //     child: Row(
                        //       mainAxisSize: MainAxisSize.min,
                        //       children: [
                        //         Icon(
                        //           Icons.refresh,
                        //           color: colors.primary,
                        //           size: 16,
                        //         ),
                        //         const SizedBox(width: 8),
                        //         Text(
                        //           'Pull down to refresh',
                        //           style: TextStyle(
                        //             color: colors.primary,
                        //             fontSize: 12,
                        //             fontWeight: FontWeight.bold,
                        //           ),
                        //         ),
                        //       ],
                        //     ),
                        //   ),
                        // ),
                        // const SizedBox(height: 80),
                      ],
                    ),
                  ),
                ),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: content,
    );
  }
}

class _ConversationCard extends ConsumerWidget {
  final Conversation conversation;

  const _ConversationCard({
    super.key,
    required this.conversation,
  });

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final isToday = now.year == dt.year && now.month == dt.month && now.day == dt.day;
    if (isToday) {
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$hour:$minute $period';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = yesterday.year == dt.year && yesterday.month == dt.month && yesterday.day == dt.day;
    if (isYesterday) {
      return 'Yesterday';
    }
    return '${dt.month}/${dt.day}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final typography = context.typography;
    final initials = getInitials(conversation.otherUserName);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final authState = ref.watch(authStateProvider).value;
    final currentUserId = authState?.id;

    final isSentByMe = (conversation.lastMessageSenderId != null &&
            conversation.lastMessageSenderId != conversation.otherUserId) ||
        (currentUserId != null && conversation.lastMessageSenderId == currentUserId);

    final showUnreadBadge = !isSentByMe && conversation.unreadCount > 0;

    final Color glassBg = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.white.withValues(alpha: 0.65);
    final Color glassBorder = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.25);
    final Color cardShadow = isDark
        ? Colors.black.withValues(alpha: 0.2)
        : colors.textPrimary.withValues(alpha: 0.05);

    final timeStr = _formatTime(conversation.lastMessageAt);
    final previewText = conversation.lastMessage != null
        ? (isSentByMe ? 'You: ${conversation.lastMessage}' : conversation.lastMessage!)
        : 'Say hi!';

    final isOnline = ref.watch(presenceProvider)[conversation.otherUserId] ?? false;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          height: 88,
          decoration: BoxDecoration(
            color: glassBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: glassBorder, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: cardShadow,
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () async {
                if (!AppThrottler.canProcess(actionId: 'open_chat_${conversation.id}')) return;
                await context.push(RouteNames.chat, extra: {
                  'conversationId': conversation.id,
                  'userId': conversation.otherUserId,
                  'userName': conversation.otherUserName,
                });
                if (context.mounted) {
                  ref.invalidate(conversationsProvider);
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    // Avatar with initials and status dot
                    GradientAvatar(
                      initials: initials,
                      avatarSeed: conversation.otherUserAvatarSeed,
                      avatarStyle: conversation.otherUserAvatarStyle,
                      gender: conversation.otherUserGender,
                      radius: 26,
                      showStatus: true,
                      isOnline: isOnline,
                      statusIndicatorSize: 14,
                    ),
                    const SizedBox(width: 14),

                    // Name & Last message preview column
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            conversation.otherUserName,
                            style: typography.bodyMedium.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            previewText,
                            style: typography.bodySmall.copyWith(
                              color: showUnreadBadge ? colors.textPrimary : colors.textSecondary,
                              fontSize: 13,
                              fontWeight: showUnreadBadge ? FontWeight.w600 : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Time and Unread Badge column
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          timeStr,
                          style: typography.bodySmall.copyWith(
                            color: showUnreadBadge ? colors.primary : colors.textSecondary,
                            fontSize: 11,
                            fontWeight: showUnreadBadge ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (showUnreadBadge)
                          Container(
                            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: colors.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Text(
                                conversation.unreadCount > 99
                                    ? '99+'
                                    : conversation.unreadCount.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          )
                        else
                          const SizedBox(height: 20),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

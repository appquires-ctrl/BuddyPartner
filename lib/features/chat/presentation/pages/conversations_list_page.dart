import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
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
/// with a clean, professional, high-density messenger list interface.
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
    final list = await ref.read(conversationsProvider.future).catchError((_) => <Conversation>[]);
    if (list.isNotEmpty) {
      final userIds = list.map((c) => c.otherUserId).toList();
      ref.read(presenceProvider.notifier).fetchPresence(userIds);
    }
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

    // Automatically fetch presence only when conversations list updates
    ref.listen<AsyncValue<List<Conversation>>>(conversationsProvider, (prev, next) {
      final list = next.valueOrNull ?? [];
      if (list.isNotEmpty) {
        final userIds = list.map((c) => c.otherUserId).toList();
        ref.read(presenceProvider.notifier).fetchPresence(userIds);
      }
    });

    final bool showSkeleton = conversationsAsync.isLoading && !conversationsAsync.hasValue;

    if (showSkeleton) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          centerTitle: true,
          toolbarHeight: 64,
          title: Text(
            'Messages',
            style: typography.titleCard.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 22,
              color: colors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
        ),
        body: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 6,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) => ConversationListItemSkeleton(itemIndex: index),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      key: const ValueKey('conversations_content'),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Column(
          children: [
            Text(
              'Messages',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
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
      // AppBar(
      //   backgroundColor: Colors.transparent,
      //   elevation: 0,
      //   scrolledUnderElevation: 0,
      //   automaticallyImplyLeading: false,
      //   centerTitle: true,
      //   toolbarHeight: 64,
      //   title: Text(
      //     'Messages',
      //     style: typography.titleCard.copyWith(
      //       fontWeight: FontWeight.w800,
      //       fontSize: 22,
      //       color: colors.textPrimary,
      //       letterSpacing: -0.3,
      //     ),
      //   ),
      // ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        color: colors.primary,
        child: conversations.isNotEmpty
            ? ListView.builder(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 80),
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                itemCount: conversations.length,
                itemBuilder: (context, index) {
                  final conv = conversations[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: _ConversationCard(
                      key: ValueKey(conv.id),
                      conversation: conv,
                    ),
                  );
                },
              )
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 40.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Center(
                        child: MatchingIllustration(
                          primaryColor: colors.primary,
                          centerCircleColor: colors.primary.withValues(alpha: 0.1),
                          icon: Icons.chat_rounded,
                          iconColor: colors.primary,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'No Conversations Yet',
                        style: typography.titleCard.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: colors.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Start connecting with people to build your chats here!',
                        style: typography.bodySmall.copyWith(
                          color: colors.textSecondary,
                          fontSize: 13,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
      ),
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

    final authState = ref.watch(authStateProvider).value;
    final currentUserId = authState?.id;

    final isSentByMe = (conversation.lastMessageSenderId != null &&
            conversation.lastMessageSenderId != conversation.otherUserId) ||
        (currentUserId != null && conversation.lastMessageSenderId == currentUserId);

    final showUnreadBadge = !isSentByMe && conversation.unreadCount > 0;

    final Color cardBg = colors.cardBackground;
    final Color cardBorder = showUnreadBadge
        ? colors.primary.withValues(alpha: 0.35)
        : colors.cardBorder;

    final timeStr = _formatTime(conversation.lastMessageAt);
    final previewText = conversation.lastMessage != null
        ? conversation.lastMessage!
        : 'Say hi!';

    final isOnline = ref.watch(presenceProvider)[conversation.otherUserId] ?? false;

    return Container(
      height: 76,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cardBorder, width: showUnreadBadge ? 1.4 : 1.0),
        boxShadow: [
          BoxShadow(
            color: showUnreadBadge
                ? colors.primary.withValues(alpha: 0.08)
                : colors.cardShadow,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () async {
            if (!AppThrottler.canProcess(actionId: 'open_chat_${conversation.id}')) return;
            HapticFeedback.lightImpact();
            await context.push(RouteNames.chat, extra: {
              'conversationId': conversation.id,
              'userId': conversation.otherUserId,
              'userName': conversation.otherUserName,
              'avatarSeed': conversation.otherUserAvatarSeed,
              'avatarStyle': conversation.otherUserAvatarStyle,
              'userAvatar': conversation.otherUserAvatar,
              'gender': conversation.otherUserGender,
            });
            if (context.mounted) {
              ref.invalidate(conversationsProvider);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14.0),
            child: Row(
              children: [
                // Avatar with initials and status dot
                GradientAvatar(
                  initials: initials,
                  avatarSeed: conversation.otherUserAvatarSeed,
                  avatarStyle: conversation.otherUserAvatarStyle,
                  gender: conversation.otherUserGender,
                  userAvatar: conversation.otherUserAvatar,
                  radius: 30,
                  showStatus: true,
                  isOnline: isOnline,
                  statusIndicatorSize: 13,
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
                          fontWeight: showUnreadBadge ? FontWeight.w800 : FontWeight.w700,
                          color: colors.textPrimary,
                          fontSize: 16.5,
                          letterSpacing: -0.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          if (isSentByMe) ...[
                            Icon(
                              Icons.done_all_rounded,
                              size: 15,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              conversation.lastMessage != null
                                  ? previewText
                                  : 'Say hi!',
                              style: typography.bodySmall.copyWith(
                                color: showUnreadBadge
                                    ? colors.textPrimary
                                    : (conversation.lastMessage != null
                                        ? colors.textSecondary
                                        : colors.textSecondary),
                                fontSize: 13,
                                fontWeight: showUnreadBadge
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),

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
                          gradient: LinearGradient(
                            colors: [
                              colors.primary,
                              const Color(0xFF9D8CF8),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: colors.primary.withValues(alpha: 0.4),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            conversation.unreadCount > 99
                                ? '99+'
                                : conversation.unreadCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
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
    );
  }
}

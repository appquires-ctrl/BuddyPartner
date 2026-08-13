import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/app/theme/app_spacing.dart';
import 'package:buddypartner/app/theme/app_radius.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/features/chat/application/conversations_provider.dart';
import 'package:buddypartner/features/chat/application/presence_provider.dart';
import 'package:buddypartner/features/chat/domain/conversation.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';
import 'package:buddypartner/core/widgets/gradient_avatar.dart';
import 'package:buddypartner/core/widgets/shimmer/skeletons/conversation_list_item_skeleton.dart';
import 'package:buddypartner/features/home/presentation/widgets/matching_illustration.dart';
import 'package:buddypartner/core/utils/app_throttler.dart';

/// ConversationsListPage displays active chat conversations
/// with a modern, high-conversion, premium UI system.
class ConversationsListPage extends ConsumerStatefulWidget {
  const ConversationsListPage({super.key});

  @override
  ConsumerState<ConversationsListPage> createState() => _ConversationsListPageState();
}

class _ConversationsListPageState extends ConsumerState<ConversationsListPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    // Auto-fetch fresh conversations on screen entry
    Future.microtask(() => ref.invalidate(conversationsProvider));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final conversationsAsync = ref.watch(conversationsProvider);

    final conversations = conversationsAsync.value ?? const [];
    final bool showSkeleton = conversationsAsync.isLoading && !conversationsAsync.hasValue;

    if (conversations.isNotEmpty) {
      final userIds = conversations.map((c) => c.otherUserId).toList();
      Future.microtask(() {
        ref.read(presenceProvider.notifier).fetchPresence(userIds);
      });
    }

    // Filter conversations by search query
    final filteredConversations = conversations.where((c) {
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase().trim();
      final name = c.otherUserName.toLowerCase();
      final msg = (c.lastMessage ?? '').toLowerCase();
      return name.contains(q) || msg.contains(q);
    }).toList();

    // Collect online users for top horizontal active bar
    final onlineConversations = conversations.where((c) {
      return ref.watch(presenceProvider)[c.otherUserId] ?? false;
    }).toList();

    Widget content;
    if (showSkeleton) {
      content = Scaffold(
        appBar: _buildAppBar(colors, typography, conversationsCount: 0),
        body: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space20, vertical: 16),
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 6,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) => ConversationListItemSkeleton(itemIndex: index),
        ),
      );
    } else {
      content = Scaffold(
        key: const ValueKey('conversations_content'),
        appBar: _buildAppBar(colors, typography, conversationsCount: conversations.length),
        body: RefreshIndicator(
          onRefresh: _handleRefresh,
          color: colors.primary,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Search Input & Active Contacts Header Section
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space20, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Search Bar
                      if (conversations.isNotEmpty) ...[
                        Container(
                          height: 46,
                          decoration: BoxDecoration(
                            color: isDark
                                ? colors.surface.withValues(alpha: 0.8)
                                : Colors.white,
                            borderRadius: AppRadius.pill,
                            border: Border.all(
                              color: colors.primary.withValues(alpha: 0.12),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: _searchController,
                            onChanged: (val) {
                              setState(() {
                                _searchQuery = val;
                              });
                            },
                            style: typography.bodyMedium.copyWith(
                              color: colors.textPrimary,
                              fontSize: 14.0,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Search chats or names...',
                              hintStyle: typography.bodySmall.copyWith(
                                color: colors.textSecondary.withValues(alpha: 0.7),
                                fontSize: 14.0,
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: colors.primary.withValues(alpha: 0.7),
                                size: 20,
                              ),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: Icon(Icons.clear_rounded, color: colors.textSecondary, size: 18),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() {
                                          _searchQuery = '';
                                        });
                                      },
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Active Now Stories Bar
                      if (onlineConversations.isNotEmpty && _searchQuery.isEmpty) ...[
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFF10B981),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Active Now (${onlineConversations.length})',
                              style: typography.bodySmall.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colors.textSecondary,
                                fontSize: 12.0,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 72,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: onlineConversations.length,
                            separatorBuilder: (context, index) => const SizedBox(width: 14),
                            itemBuilder: (context, index) {
                              final onlineConv = onlineConversations[index];
                              final initials = getInitials(onlineConv.otherUserName);
                              return GestureDetector(
                                onTap: () => _openChat(context, onlineConv),
                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: const LinearGradient(
                                          colors: [Color(0xFF10B981), Color(0xFF34D399)],
                                        ),
                                      ),
                                      child: GradientAvatar(
                                        initials: initials,
                                        avatarSeed: onlineConv.otherUserAvatarSeed,
                                        avatarStyle: onlineConv.otherUserAvatarStyle,
                                        gender: onlineConv.otherUserGender,
                                        userAvatar: onlineConv.otherUserAvatar,
                                        radius: 22,
                                        showStatus: false,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    SizedBox(
                                      width: 52,
                                      child: Text(
                                        onlineConv.otherUserName.split(' ').first,
                                        style: typography.bodySmall.copyWith(
                                          fontSize: 11.0,
                                          fontWeight: FontWeight.w600,
                                          color: colors.textPrimary,
                                        ),
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
              ),

              // Conversation Items List / Empty View
              if (filteredConversations.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final conv = filteredConversations[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ConversationCard(
                            key: ValueKey(conv.id),
                            conversation: conv,
                          ),
                        );
                      },
                      childCount: filteredConversations.length,
                    ),
                  ),
                )
              else if (_searchQuery.isNotEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 56,
                            color: colors.textSecondary.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No conversations found',
                            style: typography.titleCard.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 18.0,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No chats match "$_searchQuery"',
                            style: typography.bodySmall.copyWith(
                              color: colors.textSecondary,
                              fontSize: 13.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 40),
                        MatchingIllustration(
                          primaryColor: colors.primary,
                          centerCircleColor: colors.primary.withValues(alpha: 0.1),
                          icon: Icons.chat_bubble_outline_rounded,
                          iconColor: colors.primary,
                        ),
                        const SizedBox(height: 40),
                        Text(
                          'No Messages Yet',
                          style: typography.titleCard.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 20.0,
                            color: colors.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Start a conversation with a partner to see your chats here!',
                          style: typography.bodySmall.copyWith(
                            color: colors.textSecondary,
                            fontSize: 13.0,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: content,
    );
  }

  PreferredSizeWidget _buildAppBar(dynamic colors, dynamic typography, {required int conversationsCount}) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: AppSpacing.space20,
      title: Row(
        children: [
          Text(
            'Messages',
            style: typography.titleCard.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 24.0,
              color: colors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          if (conversationsCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                borderRadius: AppRadius.pill,
              ),
              child: Text(
                '$conversationsCount',
                style: typography.bodySmall.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12.0,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Future<void> _openChat(BuildContext context, Conversation conversation) async {
    if (!AppThrottler.canProcess(actionId: 'open_chat_${conversation.id}')) return;
    await context.push(RouteNames.chat, extra: {
      'conversationId': conversation.id,
      'userId': conversation.otherUserId,
      'userName': conversation.otherUserName,
      'avatarSeed': conversation.otherUserAvatarSeed,
      'avatarStyle': conversation.otherUserAvatarStyle,
      'userAvatar': conversation.otherUserAvatar,
      'gender': conversation.otherUserGender,
    });
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

    final Color cardBg = isDark
        ? colors.surface
        : Colors.white;
    final Color borderColor = isDark
        ? colors.border.withValues(alpha: 0.3)
        : colors.primary.withValues(alpha: 0.08);

    final timeStr = _formatTime(conversation.lastMessageAt);
    final previewText = conversation.lastMessage != null
        ? (isSentByMe ? 'You: ${conversation.lastMessage}' : conversation.lastMessage!)
        : 'Say hi!';

    final isOnline = ref.watch(presenceProvider)[conversation.otherUserId] ?? false;

    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withValues(alpha: 0.18) : colors.primary.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () async {
            if (!AppThrottler.canProcess(actionId: 'open_chat_${conversation.id}')) return;
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
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                // Avatar with initials and online status ring
                GradientAvatar(
                  initials: initials,
                  avatarSeed: conversation.otherUserAvatarSeed,
                  avatarStyle: conversation.otherUserAvatarStyle,
                  gender: conversation.otherUserGender,
                  userAvatar: conversation.otherUserAvatar,
                  radius: 25,
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
                          fontSize: 15.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        previewText,
                        style: typography.bodySmall.copyWith(
                          color: showUnreadBadge ? colors.textPrimary : colors.textSecondary,
                          fontSize: 13.0,
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
                        color: showUnreadBadge ? colors.primary : colors.textSecondary.withValues(alpha: 0.8),
                        fontSize: 11.0,
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
                              fontSize: 11.0,
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
    );
  }
}

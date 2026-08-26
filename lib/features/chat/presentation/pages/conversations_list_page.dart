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
import 'package:buddypartner/core/widgets/shimmer/app_shimmer.dart';
import 'package:buddypartner/features/home/presentation/widgets/matching_illustration.dart';
import 'package:buddypartner/features/home/presentation/providers/matched_users_provider.dart';
import 'package:buddypartner/core/utils/app_throttler.dart';

/// ConversationsListPage displays the user's active conversations
/// with an ultra-premium, modern dating app messenger design and pixel-accurate skeleton loader.
class ConversationsListPage extends ConsumerStatefulWidget {
  const ConversationsListPage({super.key});

  @override
  ConsumerState<ConversationsListPage> createState() => _ConversationsListPageState();
}

class _ConversationsListPageState extends ConsumerState<ConversationsListPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedFilter = 'all'; // 'all', 'unread', 'online'
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    ref.invalidate(conversationsProvider);
    ref.invalidate(matchedUsersProvider);
    final list = await ref.read(conversationsProvider.future).catchError((_) => <Conversation>[]);
    if (list.isNotEmpty) {
      final userIds = list.map((c) => c.otherUserId).toList();
      ref.read(presenceProvider.notifier).fetchPresence(userIds);
    }
    if (mounted) {
      setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authState = ref.watch(authStateProvider).value;
    final currentUserId = authState?.id;

    final conversationsAsync = ref.watch(conversationsProvider);
    final conversations = conversationsAsync.value ?? const [];
    final presence = ref.watch(presenceProvider);

    final matchedUsersAsync = ref.watch(matchedUsersProvider);
    final matchedUsers = (authState != null) ? (matchedUsersAsync.valueOrNull ?? const <MatchedUser>[]) : const <MatchedUser>[];

    // Automatically update presence when conversations change
    ref.listen<AsyncValue<List<Conversation>>>(conversationsProvider, (prev, next) {
      final list = next.valueOrNull ?? [];
      if (list.isNotEmpty) {
        final userIds = list.map((c) => c.otherUserId).toList();
        ref.read(presenceProvider.notifier).fetchPresence(userIds);
      }
    });

    // Compute active counts
    final int unreadCount = conversations.where((c) {
      final isSentByMe = (c.lastMessageSenderId != null && c.lastMessageSenderId != c.otherUserId) ||
          (currentUserId != null && c.lastMessageSenderId == currentUserId);
      return !isSentByMe && c.unreadCount > 0;
    }).length;

    final int onlineCount = conversations.where((c) => presence[c.otherUserId] == true).length;

    // Filter conversations
    final filteredConversations = conversations.where((c) {
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final nameMatches = c.otherUserName.toLowerCase().contains(q);
        final lastMsgMatches = c.lastMessage?.toLowerCase().contains(q) ?? false;
        if (!nameMatches && !lastMsgMatches) return false;
      }

      if (_selectedFilter == 'unread') {
        final isSentByMe = (c.lastMessageSenderId != null && c.lastMessageSenderId != c.otherUserId) ||
            (currentUserId != null && c.lastMessageSenderId == currentUserId);
        return !isSentByMe && c.unreadCount > 0;
      } else if (_selectedFilter == 'online') {
        return presence[c.otherUserId] == true;
      }

      return true;
    }).toList();

    final bool showSkeleton = conversationsAsync.isLoading && !conversationsAsync.hasValue;

    if (showSkeleton) {
      return _buildAccurateSkeletonView(context, isDark);
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _handleRefresh,
          color: colors.primary,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [
              // ── 1. Top Header ─────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(left: 20, right: 20, top: 14, bottom: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'Messages',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  color: colors.textPrimary,
                                  letterSpacing: -0.6,
                                ),
                              ),
                              if (unreadCount > 0) ...[
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF7C6AEF), Color(0xFFE879F9)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF7C6AEF).withValues(alpha: 0.35),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    '$unreadCount NEW',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            conversations.isEmpty
                                ? 'No conversations yet'
                                : '${conversations.length} active ${conversations.length == 1 ? 'chat' : 'chats'}${onlineCount > 0 ? ' • $onlineCount online now' : ''}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // ── 2. Integrated Search Bar ───────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1A2E) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? colors.border.withValues(alpha: 0.25)
                            : colors.border.withValues(alpha: 0.8),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.035),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val.trim()),
                      style: TextStyle(
                        fontSize: 14,
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search chats or messages...',
                        hintStyle: TextStyle(
                          fontSize: 13.5,
                          color: colors.textSecondary.withValues(alpha: 0.7),
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: colors.textSecondary.withValues(alpha: 0.8),
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18),
                                color: colors.textSecondary,
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                    ),
                  ),
                ),
              ),

              // ── 3. Quick Filter Chips ──────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(left: 18, right: 18, bottom: 12),
                  child: Row(
                    children: [
                      _buildFilterPill(
                        id: 'all',
                        label: 'All (${conversations.length})',
                        isSelected: _selectedFilter == 'all',
                      ),
                      const SizedBox(width: 8),
                      _buildFilterPill(
                        id: 'unread',
                        label: 'Unread ($unreadCount)',
                        isSelected: _selectedFilter == 'unread',
                        badgeColor: unreadCount > 0 ? const Color(0xFFEF4444) : null,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterPill(
                        id: 'online',
                        label: 'Online ($onlineCount)',
                        isSelected: _selectedFilter == 'online',
                        dotColor: const Color(0xFF10B981),
                      ),
                    ],
                  ),
                ),
              ),

              // ── 4. New Matches Story Tray ──────────────────────────────────
              if (matchedUsers.isNotEmpty && _searchQuery.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            children: [
                              Text(
                                'NEW MATCHES',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.9,
                                  color: colors.textSecondary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${matchedUsers.length}',
                                  style: const TextStyle(
                                    color: Color(0xFF8B5CF6),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 96,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            itemCount: matchedUsers.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 14),
                            itemBuilder: (context, index) {
                              final match = matchedUsers[index];
                              final isUserOnline = presence[match.id] ?? match.isOnline;
                              final matchInitials = getInitials(match.fullName);

                              return GestureDetector(
                                onTap: () async {
                                  if (!AppThrottler.canProcess(actionId: 'open_match_${match.id}')) return;
                                  HapticFeedback.lightImpact();
                                  await context.push(RouteNames.chat, extra: {
                                    'conversationId': 'user:${match.id}',
                                    'userId': match.id,
                                    'userName': match.fullName,
                                    'avatarSeed': match.avatarSeed,
                                    'avatarStyle': match.avatarStyle,
                                    'gender': match.gender,
                                  });
                                  if (context.mounted) {
                                    ref.invalidate(conversationsProvider);
                                  }
                                },
                                child: SizedBox(
                                  width: 66,
                                  child: Column(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(2.5),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: const LinearGradient(
                                            colors: [Color(0xFF8B5CF6), Color(0xFFFF5277)],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFF8B5CF6).withValues(alpha: 0.28),
                                              blurRadius: 8,
                                              offset: const Offset(0, 3),
                                            ),
                                          ],
                                        ),
                                        child: GradientAvatar(
                                          initials: matchInitials,
                                          avatarSeed: match.avatarSeed,
                                          avatarStyle: match.avatarStyle,
                                          gender: match.gender,
                                          radius: 26,
                                          showStatus: true,
                                          isOnline: isUserOnline,
                                          statusIndicatorSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        match.fullName.split(' ').first,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: colors.textPrimary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── 5. Conversations Section Header ───────────────────────────
              if (conversations.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 20, right: 20, top: 4, bottom: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'MESSAGES',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.9,
                            color: colors.textSecondary,
                          ),
                        ),
                        if (filteredConversations.length != conversations.length)
                          Text(
                            '${filteredConversations.length} shown',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

              // ── 6. Unified Conversations List Container ───────────────────
              if (filteredConversations.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.only(left: 16, right: 16, bottom: 90),
                  sliver: SliverToBoxAdapter(
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1C182A) : Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: isDark
                              ? colors.border.withValues(alpha: 0.25)
                              : colors.border.withValues(alpha: 0.7),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: filteredConversations.length,
                          separatorBuilder: (context, index) => Divider(
                            height: 1,
                            indent: 82,
                            endIndent: 18,
                            color: isDark
                                ? colors.border.withValues(alpha: 0.15)
                                : colors.border.withValues(alpha: 0.5),
                          ),
                          itemBuilder: (context, index) {
                            final conv = filteredConversations[index];
                            return _ConversationTile(
                              key: ValueKey(conv.id),
                              conversation: conv,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                )
              else if (conversationsAsync.hasError && conversations.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 30.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                          ),
                          child: const Icon(
                            Icons.error_outline_rounded,
                            size: 40,
                            color: Color(0xFFEF4444),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Could Not Load Chats',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: colors.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Something went wrong while fetching your messages. Please tap below to retry.',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 13.5,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _handleRefresh,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Retry'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 20.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 86,
                          height: 86,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                colors.primary.withValues(alpha: 0.18),
                                const Color(0xFFE879F9).withValues(alpha: 0.12),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Icon(
                            _searchQuery.isNotEmpty
                                ? Icons.search_off_rounded
                                : Icons.chat_bubble_outline_rounded,
                            size: 42,
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _searchQuery.isNotEmpty
                              ? 'No chats matching "$_searchQuery"'
                              : (_selectedFilter != 'all'
                                  ? 'No $_selectedFilter chats'
                                  : 'No Conversations Yet'),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: colors.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _searchQuery.isNotEmpty
                              ? 'Check your spelling or try searching another name.'
                              : 'Start connecting with people on Discover to build your chats here!',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 13.5,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (_searchQuery.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            ),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                            child: const Text('Clear Search', style: TextStyle(fontSize: 13.5)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterPill({
    required String id,
    required String label,
    required bool isSelected,
    Color? badgeColor,
    Color? dotColor,
  }) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedFilter = id);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected
                ? colors.primary
                : (isDark ? const Color(0xFF1E1A2E) : Colors.white),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? colors.primary
                  : (isDark ? colors.border.withValues(alpha: 0.25) : colors.border.withValues(alpha: 0.8)),
              width: 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: colors.primary.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dotColor != null) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white : dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? Colors.white : colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Pixel-accurate skeleton loader replicating the exact loaded Messages screen structure
  Widget _buildAccurateSkeletonView(BuildContext context, bool isDark) {
    final colors = context.colors;
    final shimmerBase = isDark ? const Color(0xFF28223D) : const Color(0xFFE8E5F2);
    final cardBg = isDark ? const Color(0xFF1C182A) : Colors.white;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 90),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Top Header
              Padding(
                padding: const EdgeInsets.only(left: 20, right: 20, top: 14, bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Messages',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: colors.textPrimary,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 2),
                    AppShimmer(
                      child: Container(
                        width: 85,
                        height: 12,
                        decoration: BoxDecoration(
                          color: shimmerBase,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. Real Search Bar Structure (with shimmering hint text)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1A2E) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? colors.border.withValues(alpha: 0.25)
                          : colors.border.withValues(alpha: 0.8),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.035),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: colors.textSecondary.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Search chats or messages...',
                        style: TextStyle(
                          fontSize: 13.5,
                          color: colors.textSecondary.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 3. Real Filter Pills (All, Unread, Online)
              Padding(
                padding: const EdgeInsets.only(left: 18, right: 18, bottom: 12),
                child: Row(
                  children: [
                    _buildFilterPill(
                      id: 'all',
                      label: 'All',
                      isSelected: true,
                    ),
                    const SizedBox(width: 8),
                    _buildFilterPill(
                      id: 'unread',
                      label: 'Unread',
                      isSelected: false,
                    ),
                    const SizedBox(width: 8),
                    _buildFilterPill(
                      id: 'online',
                      label: 'Online',
                      isSelected: false,
                      dotColor: const Color(0xFF10B981),
                    ),
                  ],
                ),
              ),

              // 4. New Matches Story Tray
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Text(
                            'NEW MATCHES',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.9,
                              color: colors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              ' • ',
                              style: TextStyle(
                                color: Color(0xFF8B5CF6),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 96,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        scrollDirection: Axis.horizontal,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: 5,
                        separatorBuilder: (_, _) => const SizedBox(width: 14),
                        itemBuilder: (context, index) {
                          return SizedBox(
                            width: 66,
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(2.5),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [
                                        const Color(0xFF8B5CF6).withValues(alpha: 0.4),
                                        const Color(0xFFFF5277).withValues(alpha: 0.4),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                  child: AppShimmer(
                                    child: Container(
                                      width: 52,
                                      height: 52,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: shimmerBase,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                AppShimmer(
                                  child: Container(
                                    width: 44,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: shimmerBase,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // 5. Messages Section Header
              Padding(
                padding: const EdgeInsets.only(left: 20, right: 20, top: 4, bottom: 4),
                child: Text(
                  'MESSAGES',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                    color: colors.textSecondary,
                  ),
                ),
              ),

              // 6. Real Unified Card with Shimmering Conversations
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 90),
                child: Container(
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: isDark
                          ? colors.border.withValues(alpha: 0.25)
                          : colors.border.withValues(alpha: 0.7),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: 5,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        indent: 82,
                        endIndent: 18,
                        color: isDark
                            ? colors.border.withValues(alpha: 0.15)
                            : colors.border.withValues(alpha: 0.5),
                      ),
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 13.0),
                          child: Row(
                            children: [
                              // Avatar (54px)
                              AppShimmer(
                                child: Container(
                                  width: 54,
                                  height: 54,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: shimmerBase,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),

                              // Name & Last Message
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    AppShimmer(
                                      child: Container(
                                        width: (index % 2 == 0) ? 120 : 90,
                                        height: 15,
                                        decoration: BoxDecoration(
                                          color: shimmerBase,
                                          borderRadius: BorderRadius.circular(5),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    AppShimmer(
                                      child: Container(
                                        width: (index % 2 == 0) ? 170 : 130,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: shimmerBase,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),

                              // Time Placeholder
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  AppShimmer(
                                    child: Container(
                                      width: 38,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: shimmerBase,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 26),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
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

class _ConversationTile extends ConsumerWidget {
  final Conversation conversation;

  const _ConversationTile({
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
    final diff = now.difference(dt);
    if (diff.inDays < 7) {
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return weekdays[dt.weekday - 1];
    }
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final initials = getInitials(conversation.otherUserName);

    final authState = ref.watch(authStateProvider).value;
    final currentUserId = authState?.id;

    final isSentByMe = (conversation.lastMessageSenderId != null &&
            conversation.lastMessageSenderId != conversation.otherUserId) ||
        (currentUserId != null && conversation.lastMessageSenderId == currentUserId);

    final showUnreadBadge = !isSentByMe && conversation.unreadCount > 0;
    final timeStr = _formatTime(conversation.lastMessageAt);
    final isOnline = ref.watch(presenceProvider)[conversation.otherUserId] ?? false;

    final isPhoto = conversation.lastMessageType == 'photo' ||
        (conversation.lastMessage?.toLowerCase().contains('[photo]') ?? false);

    final previewText = isPhoto
        ? 'Photo'
        : (conversation.lastMessage != null && conversation.lastMessage!.isNotEmpty
            ? conversation.lastMessage!
            : 'Say hi! 👋');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          if (!AppThrottler.canProcess(actionId: 'open_chat_${conversation.id}')) return;
          HapticFeedback.lightImpact();
          ref.read(conversationsProvider.notifier).markConversationAsRead(conversation.id);
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
            ref.read(conversationsProvider.notifier).refresh();
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 13.0),
          child: Row(
            children: [
              // 1. Avatar with Online Indicator (only shown if online)
              GradientAvatar(
                initials: initials,
                avatarSeed: conversation.otherUserAvatarSeed,
                avatarStyle: conversation.otherUserAvatarStyle,
                gender: conversation.otherUserGender,
                userAvatar: conversation.otherUserAvatar,
                radius: 27,
                showStatus: true,
                isOnline: isOnline,
                statusIndicatorSize: 13,
              ),
              const SizedBox(width: 14),

              // 2. Name & Last Message Column
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conversation.otherUserName,
                      style: TextStyle(
                        fontWeight: showUnreadBadge ? FontWeight.w800 : FontWeight.w700,
                        color: colors.textPrimary,
                        fontSize: 16,
                        letterSpacing: -0.2,
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
                        ] else if (isPhoto) ...[
                          Icon(
                            Icons.photo_rounded,
                            size: 14,
                            color: colors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            previewText,
                            style: TextStyle(
                              color: showUnreadBadge
                                  ? colors.textPrimary
                                  : colors.textSecondary,
                              fontSize: 13,
                              fontWeight: showUnreadBadge
                                  ? FontWeight.w700
                                  : FontWeight.w400,
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

              // 3. Time & Unread Count Badge
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    timeStr,
                    style: TextStyle(
                      color: showUnreadBadge ? colors.primary : colors.textSecondary.withValues(alpha: 0.8),
                      fontSize: 11.5,
                      fontWeight: showUnreadBadge ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (showUnreadBadge)
                    Container(
                      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [colors.primary, const Color(0xFFE879F9)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: colors.primary.withValues(alpha: 0.35),
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
    );
  }
}

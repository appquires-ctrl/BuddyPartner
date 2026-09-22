import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/core/services/socket_provider.dart';
import 'package:buddypartner/core/widgets/feedback/app_loading_indicator.dart';
import 'package:buddypartner/core/widgets/gradient_avatar.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';
import 'package:buddypartner/features/buddy/data/buddy_group_service.dart';
import 'package:buddypartner/core/widgets/feedback/in_app_notification_banner.dart';
import 'package:buddypartner/features/buddy/domain/buddy_models.dart';

class BuddyGroupChatPage extends ConsumerStatefulWidget {
  final String groupId;
  final String title;
  final int memberCount;

  const BuddyGroupChatPage({
    super.key,
    required this.groupId,
    required this.title,
    this.memberCount = 1,
  });

  @override
  ConsumerState<BuddyGroupChatPage> createState() => _BuddyGroupChatPageState();
}

class _BuddyGroupChatPageState extends ConsumerState<BuddyGroupChatPage> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic>? _groupDetails;
  bool _isLoading = true;
  bool _isSending = false;
  late final BuddyGroupService _service;
  dynamic _socket;

  @override
  void initState() {
    super.initState();
    InAppNotificationManager.activeConversationId = widget.groupId;
    _service = ref.read(buddyGroupServiceProvider);
    _socket = ref.read(socketProvider);
    _initSocket();
    _loadGroupAndMessages();
  }

  void _initSocket() {
    if (_socket != null) {
      _socket.emit('join_buddy_group_chat', {'groupId': widget.groupId});
      _socket.off('new_buddy_group_message', _handleNewMessage);
      _socket.on('new_buddy_group_message', _handleNewMessage);
      _socket.off('group_member_joined', _handleMemberJoined);
      _socket.on('group_member_joined', _handleMemberJoined);
    }
  }

  void _handleNewMessage(dynamic data) {
    if (!mounted || data == null) return;
    if (data is Map) {
      final msg = Map<String, dynamic>.from(data);
      if (msg['groupId'] == widget.groupId || msg['group_id'] == widget.groupId) {
        final id = msg['id']?.toString();
        if (id != null && _messages.any((m) => m['id']?.toString() == id)) {
          return;
        }
        setState(() {
          _messages.add(msg);
        });
        _scrollToBottom();
      }
    }
  }

  void _handleMemberJoined(dynamic data) {
    if (!mounted || data == null) return;
    if (data is Map && (data['groupId'] == widget.groupId)) {
      // Refresh details to update member list
      _loadGroupDetails();
    }
  }

  Future<void> _loadGroupAndMessages() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _service.getGroupMessages(widget.groupId),
        _service.getGroupDetails(widget.groupId).catchError((_) => <String, dynamic>{}),
      ]);

      if (mounted) {
        setState(() {
          _messages = results[0] as List<Map<String, dynamic>>;
          _groupDetails = results[1] as Map<String, dynamic>;
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadGroupDetails() async {
    if (!mounted) return;
    try {
      final details = await _service.getGroupDetails(widget.groupId);
      if (mounted) {
        setState(() => _groupDetails = details);
      }
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _textController.clear();
    HapticFeedback.selectionClick();

    final socket = _socket ?? (mounted ? ref.read(socketProvider) : null);
    if (socket != null && socket.connected == true) {
      socket.emitWithAck(
        'send_buddy_group_message',
        {
          'groupId': widget.groupId,
          'content': text,
          'type': 'text',
        },
        ack: (response) {
          if (mounted) setState(() => _isSending = false);
        },
      );
    } else {
      // REST fallback
      try {
        final newMsg = await _service.sendGroupMessage(widget.groupId, text);
        if (mounted) {
          setState(() {
            _messages.add(newMsg);
            _isSending = false;
          });
          _scrollToBottom();
        }
      } catch (_) {
        if (mounted) setState(() => _isSending = false);
      }
    }
  }

  void _showMembersSheet() {
    final members = (_groupDetails?['members'] as List<dynamic>? ?? [])
        .map((m) => BuddyGroupMember.fromJson(Map<String, dynamic>.from(m as Map)))
        .toList();

    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final colors = ctx.colors;
        final typography = ctx.typography;

        return Container(
          height: MediaQuery.of(ctx).size.height * 0.55,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              Row(
                children: [
                  Text(
                    'Group Members (${members.length}/6)',
                    style: typography.titleCard.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: colors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, color: colors.textSecondary),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: members.isEmpty
                    ? Center(
                        child: Text(
                          'No members found',
                          style: TextStyle(color: colors.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        itemCount: members.length,
                        separatorBuilder: (context, index) => Divider(height: 1, color: colors.border.withValues(alpha: 0.3)),
                        itemBuilder: (context, index) {
                          final member = members[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                            leading: GradientAvatar(
                              initials: member.fullName.isNotEmpty ? member.fullName[0].toUpperCase() : '?',
                              avatarSeed: member.avatarSeed,
                              avatarStyle: member.avatarStyle,
                              gender: member.gender,
                              radius: 20,
                            ),
                            title: Text(
                              member.fullName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: colors.textPrimary,
                              ),
                            ),
                            trailing: member.isHost
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF9333EA), Color(0xFF6B21A8)],
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      '👑 HOST',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  )
                                : Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: colors.surfaceMuted,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Member',
                                      style: TextStyle(
                                        color: colors.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    if (InAppNotificationManager.activeConversationId == widget.groupId) {
      InAppNotificationManager.activeConversationId = null;
    }
    if (_socket != null) {
      try {
        _socket.emit('leave_buddy_group_chat', {'groupId': widget.groupId});
        _socket.off('new_buddy_group_message', _handleNewMessage);
        _socket.off('group_member_joined', _handleMemberJoined);
      } catch (_) {}
    }
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final currentUserId = ref.watch(authStateProvider).value?.id;
    final memberCount = _groupDetails?['member_count'] ?? widget.memberCount;
    final displayTitle = _groupDetails?['title'] ?? widget.title;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0.5,
        backgroundColor: colors.surface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: colors.textPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        titleSpacing: 0,
        title: InkWell(
          onTap: _showMembersSheet,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF6B21A8), Color(0xFF9333EA)],
                      ),
                    ),
                    child: Image.asset(
                      'assets/images/garba_buddy.png',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.groups_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayTitle,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '$memberCount/6 Members • View',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            color: colors.textSecondary,
            onPressed: _showMembersSheet,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Messages View
            Expanded(
              child: _isLoading
                  ? const Center(child: AppLoadingIndicator(size: 32))
                  : _messages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF9333EA).withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.celebration_rounded, color: Color(0xFF9333EA), size: 36),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Welcome to the Garba Group!',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: colors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Start chatting with your group buddies.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            final isSystem = msg['type'] == 'system';
                            final senderId = msg['sender_id'] ?? msg['senderId'];
                            final isMe = (currentUserId != null && senderId == currentUserId);
                            final content = msg['content'] as String? ?? '';
                            final senderName = msg['sender_name'] ?? msg['senderName'] ?? 'Member';
                            final avatarSeed = msg['sender_avatar_seed'] ?? msg['senderAvatarSeed'] as String?;
                            final avatarStyle = msg['sender_avatar_style'] ?? msg['senderAvatarStyle'] as String?;
                            final gender = msg['sender_gender'] ?? msg['senderGender'] as String?;

                            if (isSystem) {
                              return Center(
                                child: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: colors.surfaceMuted,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: colors.border.withValues(alpha: 0.4)),
                                  ),
                                  child: Text(
                                    content,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colors.textSecondary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              );
                            }

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if (!isMe) ...[
                                    GradientAvatar(
                                      initials: senderName.isNotEmpty ? senderName[0].toUpperCase() : '?',
                                      avatarSeed: avatarSeed,
                                      avatarStyle: avatarStyle,
                                      gender: gender,
                                      radius: 14,
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Flexible(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: isMe ? colors.primary : colors.surface,
                                        borderRadius: BorderRadius.only(
                                          topLeft: const Radius.circular(18),
                                          topRight: const Radius.circular(18),
                                          bottomLeft: Radius.circular(isMe ? 18 : 4),
                                          bottomRight: Radius.circular(isMe ? 4 : 18),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.04),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                        children: [
                                          if (!isMe) ...[
                                            Text(
                                              senderName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                                color: Color(0xFF9333EA),
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                          ],
                                          Text(
                                            content,
                                            style: TextStyle(
                                              fontSize: 14.5,
                                              color: isMe ? Colors.white : colors.textPrimary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),

            // Bottom Input Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(top: BorderSide(color: colors.border.withValues(alpha: 0.5))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: colors.surfaceMuted,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _textController,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: const InputDecoration(
                          hintText: 'Plan your Garba night...',
                          hintStyle: TextStyle(fontSize: 14),
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF9333EA), Color(0xFF6B21A8)],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: _isSending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

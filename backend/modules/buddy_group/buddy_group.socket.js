const db = require('../../db');
const { sendMulticastPushNotification } = require('../../services/firebase.service');
const { buddyGroupService } = require('./buddy_group.service');

/**
 * Socket.IO handlers for real-time Buddy Group Broadcasts & Group Chat.
 * Scaled for 5,000 CCU with Redis Adapter.
 */
function registerBuddyGroupSocketHandlers(io, socket, redis) {
  // 1. Join real-time group chat room
  socket.on('join_buddy_group_chat', ({ groupId }) => {
    if (groupId && typeof groupId === 'string') {
      const room = `buddy_group:${groupId}`;
      socket.join(room);
    }
  });

  // 2. Leave group chat room
  socket.on('leave_buddy_group_chat', ({ groupId }) => {
    if (groupId && typeof groupId === 'string') {
      socket.leave(`buddy_group:${groupId}`);
    }
  });

  // 3. Send message via Socket for ultra-low latency
  socket.on('send_buddy_group_message', async ({ groupId, content, type = 'text' }, callback) => {
    try {
      if (!groupId || !content || !content.trim()) {
        if (typeof callback === 'function') callback({ error: 'INVALID_PAYLOAD' });
        return;
      }

      const message = await buddyGroupService.sendMessage({
        groupId,
        senderId: socket.userId,
        content,
        type,
      });

      // Broadcast to all active users in the group room
      io.to(`buddy_group:${groupId}`).emit('new_buddy_group_message', message);

      if (typeof callback === 'function') {
        callback({ success: true, message });
      }

      // Background FCM multicast for group members not currently online in this group room
      setImmediate(async () => {
        try {
          const membersRes = await db.query(
            `SELECT u.id, u.fcm_token, bg.title
             FROM public.buddy_group_members bgm
             JOIN public.users u ON u.id = bgm.user_id
             JOIN public.buddy_groups bg ON bg.id = bgm.group_id
             WHERE bgm.group_id = $1 
               AND bgm.user_id != $2 
               AND u.fcm_token IS NOT NULL
               AND (u.is_banned IS FALSE OR u.is_banned IS NULL)`,
            [groupId, socket.userId]
          );

          if (membersRes.rows.length === 0) return;

          const tokens = membersRes.rows.map(r => r.fcm_token);
          const groupTitle = membersRes.rows[0]?.title || 'Garba Buddy Group';

          await sendMulticastPushNotification({
            tokens,
            notification: {
              title: groupTitle,
              body: `${message.senderName}: ${message.content.substring(0, 100)}`,
            },
            data: {
              type: 'BUDDY_GROUP_MESSAGE',
              groupId,
              title: groupTitle,
            },
          });
        } catch (fcmErr) {
          console.warn('⚠️ [BuddyGroup] FCM multicast push error:', fcmErr.message);
        }
      });
    } catch (err) {
      console.error('❌ Error in send_buddy_group_message:', err.message);
      if (typeof callback === 'function') {
        callback({ error: err.message });
      }
    }
  });
}

/**
 * Broadcast new Garba Group request to matching city rooms.
 */
function broadcastNewBuddyGroup(io, group) {
  if (!io || !group || !group.city) return;

  const normalizedCity = group.city.trim().toLowerCase();
  const targetGender = (group.target_gender || 'all').trim().toLowerCase();

  const payload = {
    ...group,
    isGroup: true,
  };

  if (targetGender === 'all') {
    io.to(`buddy:city:${normalizedCity}:male`)
      .to(`buddy:city:${normalizedCity}:female`)
      .emit('new_buddy_group_request', payload);
  } else {
    io.to(`buddy:city:${normalizedCity}:${targetGender}`).emit('new_buddy_group_request', payload);
  }
}

/**
 * Broadcast updated slots (e.g. 4/6 joined) to city rooms so broadcast cards update live.
 */
function broadcastGroupSlotUpdate(io, { groupId, city, memberCount, maxMembers, status }) {
  if (!io || !city) return;

  const normalizedCity = city.trim().toLowerCase();
  const payload = {
    groupId,
    memberCount,
    maxMembers,
    status,
  };

  io.to(`buddy:city:${normalizedCity}:male`)
    .to(`buddy:city:${normalizedCity}:female`)
    .emit('buddy_group_slot_update', payload);

  if (status === 'full') {
    io.to(`buddy:city:${normalizedCity}:male`)
      .to(`buddy:city:${normalizedCity}:female`)
      .emit('buddy_group_full', { groupId });
  }
}

/**
 * Notify participants inside the group chat room that someone joined.
 */
function notifyGroupMemberJoined(io, { groupId, joinedMember, memberCount }) {
  if (!io || !groupId) return;

  io.to(`buddy_group:${groupId}`).emit('group_member_joined', {
    groupId,
    joinedMember,
    memberCount,
  });
}

module.exports = {
  registerBuddyGroupSocketHandlers,
  broadcastNewBuddyGroup,
  broadcastGroupSlotUpdate,
  notifyGroupMemberJoined,
};

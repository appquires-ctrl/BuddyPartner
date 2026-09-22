const db = require('../../db');
const { WalletService } = require('../wallet/wallet.service');
const { ModerationService } = require('../moderation/moderation.service');
const { subscriptionsService } = require('../subscriptions/subscriptions.service');

class BuddyGroupService {
  _normalizeCity(city) {
    if (!city || typeof city !== 'string') return '';
    return city.trim().toLowerCase();
  }

  _isValidUUID(uuid) {
    return typeof uuid === 'string' && /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(uuid);
  }

  /**
   * Host initiates a new 6-person Garba Buddy Group Broadcast.
   * Host is deducted exactly 509 coins (spendable-first, then earned).
   * Host is automatically registered as Member #1 (role: 'host').
   */
  async createGroupBroadcast({ hostId, city, targetGender = 'all', title = null, idempotencyKey = null }) {
    if (!this._isValidUUID(hostId)) {
      const err = new Error('Invalid host ID');
      err.statusCode = 400;
      throw err;
    }

    const normalizedCity = this._normalizeCity(city);
    if (!normalizedCity) {
      const err = new Error('City is required to broadcast a Garba group');
      err.statusCode = 400;
      throw err;
    }

    // 1. Check Moderation Status
    const modStatus = await ModerationService.isUserBlocked(hostId);
    if (modStatus.isBanned || modStatus.isSuspended) {
      const err = new Error('Account is restricted from creating group requests');
      err.statusCode = 403;
      throw err;
    }

    // 2. Check Subscription
    const isSub = await subscriptionsService.isSubscribed(hostId);
    if (!isSub) {
      const err = new Error('An active membership subscription is required to host a Garba buddy group');
      err.code = 'ACTIVE_SUBSCRIPTION_REQUIRED';
      err.statusCode = 403;
      throw err;
    }

    const HOST_COIN_COST = 509;
    const groupTitle = (title && title.trim()) ? title.trim() : 'Garba Buddy Group';

    const client = await db.pool.connect();
    try {
      await client.query('BEGIN');

      // 1. Check idempotency if key provided
      if (idempotencyKey) {
        const existing = await client.query(
          `SELECT bg.*, u.full_name as host_name, u.avatar_seed as host_avatar_seed, u.avatar_style as host_avatar_style, u.gender as host_gender
           FROM public.buddy_groups bg
           JOIN public.users u ON u.id = bg.initiator_id
           WHERE bg.idempotency_key = $1`,
          [idempotencyKey]
        );
        if (existing.rows.length > 0) {
          await client.query('COMMIT');
          console.log(`🔁 [BuddyGroupService.createGroupBroadcast] Idempotency hit: ${idempotencyKey}`);
          return existing.rows[0];
        }
      }

      // 3. Debit 509 Coins from Host (Spendable-first, then earned)
      const debitRes = await WalletService.debitCoins({
        userId: hostId,
        amount: HOST_COIN_COST,
        reason: 'buddy_spend',
        referenceId: idempotencyKey || `group_${Date.now()}`,
        idempotencyKey: idempotencyKey ? `tx_group_${idempotencyKey}` : null,
        client,
      });

      if (!debitRes.success) {
        await client.query('ROLLBACK');
        const bal = await WalletService.getBalance(hostId);
        const err = new Error(`Insufficient coins: 509 coins required to host a Garba buddy group (current balance: ${bal.balance} coins).`);
        err.code = 'INSUFFICIENT_COINS';
        err.statusCode = 400;
        throw err;
      }

      // 4. Create Group Row
      const insertGroup = await client.query(
        `INSERT INTO public.buddy_groups (
           initiator_id, title, buddy_type, city, target_gender,
           host_coin_cost, max_members, member_count, status, idempotency_key
         ) VALUES ($1, $2, 'garba', $3, $4, $5, 6, 1, 'open', $6)
         RETURNING *`,
        [hostId, groupTitle, normalizedCity, targetGender || 'all', HOST_COIN_COST, idempotencyKey]
      );
      const group = insertGroup.rows[0];

      // 5. Add Host as Member #1
      await client.query(
        `INSERT INTO public.buddy_group_members (group_id, user_id, role)
         VALUES ($1, $2, 'host')`,
        [group.id, hostId]
      );

      // 6. Insert Welcome System Message
      await client.query(
        `INSERT INTO public.buddy_group_messages (group_id, sender_id, content, type)
         VALUES ($1, $2, 'Welcome to Garba Buddy Group! Up to 6 members can join and plan Garba together.', 'system')`,
        [group.id, hostId]
      );

      // Update wallet transaction reference_id to the group ID
      if (debitRes.transactionId) {
        await client.query(
          `UPDATE public.wallet_transactions
           SET reference_id = $1
           WHERE id = $2`,
          [group.id, debitRes.transactionId]
        );
      }

      await client.query('COMMIT');

      // Fetch host details for client
      const hostRes = await db.query(
        `SELECT full_name, avatar_seed, avatar_style, gender FROM public.users WHERE id = $1`,
        [hostId]
      );
      const hostUser = hostRes.rows[0] || {};

      return {
        ...group,
        host: {
          id: hostId,
          fullName: hostUser.full_name || 'Host',
          avatarSeed: hostUser.avatar_seed,
          avatarStyle: hostUser.avatar_style,
          gender: hostUser.gender,
        },
      };
    } catch (err) {
      await client.query('ROLLBACK').catch(() => {});
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * User joins a Garba Buddy Group.
   * FREE: 0 coins cost for joining members.
   * ZERO OTP: Direct admission to group.
   * Atomic check-and-increment query guarantees no over-acceptance under 5,000 CCU flash crowd.
   */
  async joinGroup({ groupId, userId }) {
    if (!this._isValidUUID(groupId) || !this._isValidUUID(userId)) {
      const err = new Error('Invalid group or user ID');
      err.statusCode = 400;
      throw err;
    }

    // 1. Check Moderation Status
    const modStatus = await ModerationService.isUserBlocked(userId);
    if (modStatus.isBanned || modStatus.isSuspended) {
      const err = new Error('Account is restricted from joining groups');
      err.statusCode = 403;
      throw err;
    }

    // 2. Check if user is ALREADY a member (idempotent join)
    const existingMember = await db.query(
      `SELECT bgm.role, bg.id, bg.title, bg.member_count, bg.max_members, bg.status, bg.city
       FROM public.buddy_group_members bgm
       JOIN public.buddy_groups bg ON bg.id = bgm.group_id
       WHERE bgm.group_id = $1 AND bgm.user_id = $2`,
      [groupId, userId]
    );

    if (existingMember.rows.length > 0) {
      return {
        alreadyMember: true,
        groupId,
        group: existingMember.rows[0],
      };
    }

    // 3. Atomic Join Query (locks row, verifies member_count < 6, inserts membership)
    const client = await db.pool.connect();
    try {
      await client.query('BEGIN');

      const joinSql = `
        WITH updated_group AS (
          UPDATE public.buddy_groups
          SET 
            member_count = member_count + 1,
            status = CASE WHEN member_count + 1 >= max_members THEN 'full' ELSE 'open' END
          WHERE id = $1 
            AND member_count < max_members 
            AND status = 'open'
          RETURNING id, title, member_count, max_members, status, city
        )
        INSERT INTO public.buddy_group_members (group_id, user_id, role)
        SELECT id, $2, 'member' 
        FROM updated_group
        RETURNING group_id, user_id, role, joined_at;
      `;

      const joinResult = await client.query(joinSql, [groupId, userId]);

      if (joinResult.rows.length === 0) {
        await client.query('ROLLBACK');
        // Check if group exists but is full or cancelled
        const checkGroup = await db.query(
          `SELECT status, member_count, max_members FROM public.buddy_groups WHERE id = $1`,
          [groupId]
        );
        if (checkGroup.rows.length === 0) {
          const err = new Error('Garba group not found');
          err.statusCode = 404;
          throw err;
        }
        const err = new Error('This Garba group is already full (6/6 members)!');
        err.code = 'GROUP_FULL';
        err.statusCode = 409;
        throw err;
      }

      // 4. Fetch joining user's profile for system announcement
      const userRes = await client.query(
        `SELECT full_name FROM public.users WHERE id = $1`,
        [userId]
      );
      const userName = userRes.rows[0]?.full_name || 'A new member';

      // 5. Insert system join message
      await client.query(
        `INSERT INTO public.buddy_group_messages (group_id, sender_id, content, type)
         VALUES ($1, $2, $3, 'system')`,
        [groupId, userId, `${userName} joined the Garba group!`]
      );

      await client.query('COMMIT');

      // Fetch fresh group state
      const freshGroup = await db.query(
        `SELECT id, title, city, member_count, max_members, status FROM public.buddy_groups WHERE id = $1`,
        [groupId]
      );

      return {
        alreadyMember: false,
        groupId,
        group: freshGroup.rows[0],
        joinedMember: {
          userId,
          fullName: userName,
        },
      };
    } catch (err) {
      await client.query('ROLLBACK').catch(() => {});
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * List open Garba Buddy Groups in a city that have available slots (< 6 members).
   */
  async listOpenGroups({ city, userId, limit = 20, offset = 0 }) {
    const normalizedCity = this._normalizeCity(city);
    const parsedLimit = Math.min(Math.max(parseInt(limit, 10) || 20, 1), 50);
    const parsedOffset = Math.max(parseInt(offset, 10) || 0, 0);

    const query = `
      SELECT 
        bg.id,
        bg.initiator_id,
        bg.title,
        bg.buddy_type,
        bg.city,
        bg.target_gender,
        bg.host_coin_cost,
        bg.max_members,
        bg.member_count,
        bg.status,
        bg.created_at,
        u.full_name as host_name,
        u.avatar_seed as host_avatar_seed,
        u.avatar_style as host_avatar_style,
        u.gender as host_gender,
        EXISTS (
          SELECT 1 FROM public.buddy_group_members bgm 
          WHERE bgm.group_id = bg.id AND bgm.user_id = $2
        ) as is_member
      FROM public.buddy_groups bg
      JOIN public.users u ON u.id = bg.initiator_id
      WHERE LOWER(TRIM(bg.city)) = $1
        AND bg.status = 'open'
        AND bg.member_count < bg.max_members
      ORDER BY bg.created_at DESC
      LIMIT $3 OFFSET $4;
    `;

    const result = await db.query(query, [normalizedCity, userId, parsedLimit, parsedOffset]);
    return result.rows;
  }

  /**
   * Get all Garba groups the user has joined (for the Chat Navigation Tab "Groups" section).
   */
  async getMyGroups(userId) {
    if (!this._isValidUUID(userId)) return [];

    const query = `
      SELECT 
        bg.id,
        bg.initiator_id,
        bg.title,
        bg.buddy_type,
        bg.city,
        bg.max_members,
        bg.member_count,
        bg.status,
        bg.last_message_at,
        bg.created_at,
        bgm.role,
        bgm.joined_at,
        bgm.last_read_at,
        host.full_name as host_name,
        host.avatar_seed as host_avatar_seed,
        host.avatar_style as host_avatar_style,
        -- Subquery for last message
        last_msg.content as last_message_content,
        last_msg.type as last_message_type,
        last_msg.created_at as last_message_time,
        sender.full_name as last_message_sender_name,
        -- Subquery for unread messages count
        (
          SELECT COUNT(*)::int
          FROM public.buddy_group_messages m
          WHERE m.group_id = bg.id
            AND m.created_at > COALESCE(bgm.last_read_at, bgm.joined_at)
            AND m.sender_id != $1
        ) as unread_count
      FROM public.buddy_group_members bgm
      JOIN public.buddy_groups bg ON bg.id = bgm.group_id
      JOIN public.users host ON host.id = bg.initiator_id
      LEFT JOIN LATERAL (
        SELECT m.content, m.type, m.created_at, m.sender_id
        FROM public.buddy_group_messages m
        WHERE m.group_id = bg.id
        ORDER BY m.created_at DESC
        LIMIT 1
      ) last_msg ON true
      LEFT JOIN public.users sender ON sender.id = last_msg.sender_id
      WHERE bgm.user_id = $1
      ORDER BY COALESCE(bg.last_message_at, bg.created_at) DESC;
    `;

    const result = await db.query(query, [userId]);
    return result.rows;
  }

  /**
   * Get group details along with all 6 member profiles.
   */
  async getGroupDetails(groupId, userId) {
    // 1. Verify membership
    const memberCheck = await db.query(
      `SELECT role FROM public.buddy_group_members WHERE group_id = $1 AND user_id = $2`,
      [groupId, userId]
    );
    if (memberCheck.rows.length === 0) {
      const err = new Error('You are not a member of this group');
      err.statusCode = 403;
      throw err;
    }

    // 2. Fetch group
    const groupRes = await db.query(
      `SELECT bg.*, u.full_name as host_name, u.avatar_seed as host_avatar_seed
       FROM public.buddy_groups bg
       JOIN public.users u ON u.id = bg.initiator_id
       WHERE bg.id = $1`,
      [groupId]
    );
    if (groupRes.rows.length === 0) {
      const err = new Error('Group not found');
      err.statusCode = 404;
      throw err;
    }

    // 3. Fetch all members
    const membersRes = await db.query(
      `SELECT bgm.role, bgm.joined_at, u.id, u.full_name, u.avatar_seed, u.avatar_style, u.gender
       FROM public.buddy_group_members bgm
       JOIN public.users u ON u.id = bgm.user_id
       WHERE bgm.group_id = $1
       ORDER BY CASE WHEN bgm.role = 'host' THEN 0 ELSE 1 END, bgm.joined_at ASC`,
      [groupId]
    );

    return {
      ...groupRes.rows[0],
      myRole: memberCheck.rows[0].role,
      members: membersRes.rows,
    };
  }

  /**
   * Fetch paginated message history for a group.
   */
  async getGroupMessages(groupId, userId, limit = 50, before = null) {
    // Verify membership
    const memCheck = await db.query(
      `SELECT role FROM public.buddy_group_members WHERE group_id = $1 AND user_id = $2`,
      [groupId, userId]
    );
    if (memCheck.rows.length === 0) {
      const err = new Error('Access denied: You are not a member of this group');
      err.statusCode = 403;
      throw err;
    }

    // Update last_read_at
    await db.query(
      `UPDATE public.buddy_group_members SET last_read_at = NOW() WHERE group_id = $1 AND user_id = $2`,
      [groupId, userId]
    );

    const parsedLimit = Math.min(Math.max(parseInt(limit, 10) || 50, 1), 100);

    let query;
    let params;
    if (before) {
      query = `
        SELECT 
          m.id,
          m.group_id,
          m.sender_id,
          m.content,
          m.type,
          m.created_at,
          u.full_name as sender_name,
          u.avatar_seed as sender_avatar_seed,
          u.avatar_style as sender_avatar_style,
          u.gender as sender_gender
        FROM public.buddy_group_messages m
        JOIN public.users u ON u.id = m.sender_id
        WHERE m.group_id = $1 AND m.created_at < $2
        ORDER BY m.created_at DESC
        LIMIT $3;
      `;
      params = [groupId, before, parsedLimit];
    } else {
      query = `
        SELECT 
          m.id,
          m.group_id,
          m.sender_id,
          m.content,
          m.type,
          m.created_at,
          u.full_name as sender_name,
          u.avatar_seed as sender_avatar_seed,
          u.avatar_style as sender_avatar_style,
          u.gender as sender_gender
        FROM public.buddy_group_messages m
        JOIN public.users u ON u.id = m.sender_id
        WHERE m.group_id = $1
        ORDER BY m.created_at DESC
        LIMIT $2;
      `;
      params = [groupId, parsedLimit];
    }

    const res = await db.query(query, params);
    return res.rows.reverse(); // Return in chronological order
  }

  /**
   * Send a text/image message in the group.
   */
  async sendMessage({ groupId, senderId, content, type = 'text' }) {
    if (!content || !content.trim()) {
      throw new Error('Message content cannot be empty');
    }

    // Verify sender is in group
    const memCheck = await db.query(
      `SELECT role FROM public.buddy_group_members WHERE group_id = $1 AND user_id = $2`,
      [groupId, senderId]
    );
    if (memCheck.rows.length === 0) {
      const err = new Error('You are not a member of this group');
      err.statusCode = 403;
      throw err;
    }

    // Insert message
    const insertRes = await db.query(
      `INSERT INTO public.buddy_group_messages (group_id, sender_id, content, type)
       VALUES ($1, $2, $3, $4)
       RETURNING *`,
      [groupId, senderId, content.trim(), type]
    );
    const message = insertRes.rows[0];

    // Update group's last_message_at
    await db.query(
      `UPDATE public.buddy_groups SET last_message_at = NOW() WHERE id = $1`,
      [groupId]
    );

    // Fetch sender profile
    const senderRes = await db.query(
      `SELECT full_name, avatar_seed, avatar_style, gender FROM public.users WHERE id = $1`,
      [senderId]
    );
    const sender = senderRes.rows[0] || {};

    return {
      id: message.id,
      groupId: message.group_id,
      senderId: message.sender_id,
      senderName: sender.full_name || 'User',
      senderAvatarSeed: sender.avatar_seed,
      senderAvatarStyle: sender.avatar_style,
      senderGender: sender.gender,
      content: message.content,
      type: message.type,
      createdAt: message.created_at,
    };
  }
}

module.exports = {
  buddyGroupService: new BuddyGroupService(),
};

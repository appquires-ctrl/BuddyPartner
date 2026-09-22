const express = require('express');
const { authMiddleware } = require('../../middleware/auth.middleware');
const { buddyGroupService } = require('./buddy_group.service');
const {
  broadcastNewBuddyGroup,
  broadcastGroupSlotUpdate,
  notifyGroupMemberJoined,
} = require('./buddy_group.socket');
const db = require('../../db');

const router = express.Router();

/**
 * POST /api/buddy-group/broadcast
 * Host initiates a 6-person Garba Buddy Group broadcast.
 * Deducts 509 coins from host.
 */
router.post('/broadcast', authMiddleware, async (req, res) => {
  try {
    const { city, targetGender, title } = req.body;
    const idempotencyKey = req.body.idempotencyKey || req.headers['x-idempotency-key'] || null;

    let targetCity = city;
    if (!targetCity) {
      const userRes = await db.query('SELECT city FROM public.users WHERE id = $1', [req.user.id]);
      targetCity = userRes.rows[0]?.city;
    }

    if (!targetCity) {
      return res.status(400).json({ error: 'City is required to broadcast a Garba group' });
    }

    const group = await buddyGroupService.createGroupBroadcast({
      hostId: req.user.id,
      city: targetCity,
      targetGender: targetGender || 'all',
      title: title || 'Garba Buddy Group',
      idempotencyKey,
    });

    const io = req.app.get('io');
    if (io) {
      broadcastNewBuddyGroup(io, group);
    }

    res.status(201).json({
      success: true,
      group,
    });
  } catch (err) {
    console.error('❌ Error in POST /api/buddy-group/broadcast:', err.message);
    const status = err.statusCode || 500;
    res.status(status).json({
      error: err.code || 'FAILED_TO_CREATE_GROUP',
      message: err.message || 'Failed to create Garba group',
    });
  }
});

/**
 * GET /api/buddy-group/open
 * List open Garba Buddy Groups in the user's city (< 6 members).
 */
router.get('/open', authMiddleware, async (req, res) => {
  try {
    let { city, limit, offset } = req.query;

    if (!city) {
      const userRes = await db.query('SELECT city FROM public.users WHERE id = $1', [req.user.id]);
      city = userRes.rows[0]?.city;
    }

    if (!city) {
      return res.json({ success: true, groups: [] });
    }

    const groups = await buddyGroupService.listOpenGroups({
      city,
      userId: req.user.id,
      limit,
      offset,
    });

    res.json({
      success: true,
      groups,
    });
  } catch (err) {
    console.error('❌ Error in GET /api/buddy-group/open:', err.message);
    res.status(500).json({
      error: 'FAILED_TO_LIST_GROUPS',
      message: err.message || 'Failed to list open Garba groups',
    });
  }
});

/**
 * POST /api/buddy-group/:id/join
 * Join a Garba Buddy Group (FREE: 0 coins, ZERO OTP).
 * Atomic reservation ensures capacity <= 6 under 5,000 CCU concurrency.
 */
router.post('/:id/join', authMiddleware, async (req, res) => {
  try {
    const groupId = req.params.id;
    const userId = req.user.id;

    const result = await buddyGroupService.joinGroup({
      groupId,
      userId,
    });

    const io = req.app.get('io');
    if (io && !result.alreadyMember) {
      // 1. Broadcast updated slot count to city rooms
      broadcastGroupSlotUpdate(io, {
        groupId: result.groupId,
        city: result.group.city,
        memberCount: result.group.member_count,
        maxMembers: result.group.max_members,
        status: result.group.status,
      });

      // 2. Notify members inside the group chat
      notifyGroupMemberJoined(io, {
        groupId: result.groupId,
        joinedMember: result.joinedMember,
        memberCount: result.group.member_count,
      });
    }

    res.json({
      success: true,
      ...result,
      message: result.alreadyMember
        ? 'You are already a member of this group'
        : 'Successfully joined the Garba group!',
    });
  } catch (err) {
    console.error(`❌ Error in POST /api/buddy-group/${req.params.id}/join:`, err.message);
    const status = err.statusCode || 500;
    res.status(status).json({
      error: err.code || 'FAILED_TO_JOIN_GROUP',
      message: err.message || 'Failed to join Garba group',
    });
  }
});

/**
 * GET /api/buddy-group/my-groups
 * Fetch all Garba groups the user has joined (for Chat Tab -> Groups section).
 */
router.get('/my-groups', authMiddleware, async (req, res) => {
  try {
    const groups = await buddyGroupService.getMyGroups(req.user.id);
    res.json({
      success: true,
      groups,
    });
  } catch (err) {
    console.error('❌ Error in GET /api/buddy-group/my-groups:', err.message);
    res.status(500).json({
      error: 'FAILED_TO_FETCH_MY_GROUPS',
      message: err.message || 'Failed to fetch your Garba groups',
    });
  }
});

/**
 * GET /api/buddy-group/:id/details
 * Fetch group details & all 6 member profiles.
 */
router.get('/:id/details', authMiddleware, async (req, res) => {
  try {
    const details = await buddyGroupService.getGroupDetails(req.params.id, req.user.id);
    res.json({
      success: true,
      group: details,
    });
  } catch (err) {
    console.error(`❌ Error in GET /api/buddy-group/${req.params.id}/details:`, err.message);
    const status = err.statusCode || 500;
    res.status(status).json({
      error: err.code || 'FAILED_TO_FETCH_DETAILS',
      message: err.message || 'Failed to fetch group details',
    });
  }
});

/**
 * GET /api/buddy-group/:id/messages
 * Fetch paginated group message history.
 */
router.get('/:id/messages', authMiddleware, async (req, res) => {
  try {
    const { limit, before } = req.query;
    const messages = await buddyGroupService.getGroupMessages(
      req.params.id,
      req.user.id,
      limit,
      before
    );
    res.json({
      success: true,
      messages,
    });
  } catch (err) {
    console.error(`❌ Error in GET /api/buddy-group/${req.params.id}/messages:`, err.message);
    const status = err.statusCode || 500;
    res.status(status).json({
      error: err.code || 'FAILED_TO_FETCH_MESSAGES',
      message: err.message || 'Failed to fetch group messages',
    });
  }
});

/**
 * POST /api/buddy-group/:id/messages
 * Send a message via REST.
 */
router.post('/:id/messages', authMiddleware, async (req, res) => {
  try {
    const { content, type } = req.body;
    const message = await buddyGroupService.sendMessage({
      groupId: req.params.id,
      senderId: req.user.id,
      content,
      type: type || 'text',
    });

    const io = req.app.get('io');
    if (io) {
      io.to(`buddy_group:${req.params.id}`).emit('new_buddy_group_message', message);
    }

    res.status(201).json({
      success: true,
      message,
    });
  } catch (err) {
    console.error(`❌ Error in POST /api/buddy-group/${req.params.id}/messages:`, err.message);
    const status = err.statusCode || 500;
    res.status(status).json({
      error: err.code || 'FAILED_TO_SEND_MESSAGE',
      message: err.message || 'Failed to send group message',
    });
  }
});

module.exports = router;

const express = require('express');
const { authMiddleware } = require('../../middleware/auth.middleware');
const { MessagingService } = require('./messaging.service');

const router = express.Router();
const messagingService = new MessagingService();

// ── GET /api/conversations ────────────────────────────────────────────────
// List all conversations for the authenticated user
router.get('/conversations', authMiddleware, async (req, res) => {
  try {
    const conversations = await messagingService.getConversations(req.user.id);
    res.json({ conversations });
  } catch (err) {
    console.error('Error fetching conversations:', err.message);
    res.status(500).json({ error: 'Failed to fetch conversations' });
  }
});

// ── POST /api/conversations ───────────────────────────────────────────────
// Find or create a conversation with another user
router.post('/conversations', authMiddleware, async (req, res) => {
  try {
    const { otherUserId } = req.body;
    if (!otherUserId) {
      return res.status(400).json({ error: 'otherUserId is required' });
    }

    const conversation = await messagingService.findOrCreateConversation(
      req.user.id,
      otherUserId
    );

    res.json({ conversation });
  } catch (err) {
    console.error('Error creating conversation:', err.message);
    if (err.message.includes('block') || err.message.includes('Cannot start a conversation')) {
      return res.status(403).json({ error: err.message });
    }
    if (err.message.includes('User not found')) {
      return res.status(404).json({ error: err.message });
    }
    if (err.message.includes('yourself') || err.message.includes('Invalid') || err.message.includes('required')) {
      return res.status(400).json({ error: err.message });
    }
    res.status(500).json({ error: err.message || 'Failed to create conversation' });
  }
});

// ── GET /api/conversations/:id/messages ───────────────────────────────────
// Get paginated messages for a conversation
router.get('/conversations/:id/messages', authMiddleware, async (req, res) => {
  try {
    const { id } = req.params;
    const { cursor, limit } = req.query;

    const result = await messagingService.getMessages(
      id,
      req.user.id,
      cursor || null,
      parseInt(limit) || 30
    );

    res.json(result);
  } catch (err) {
    console.error('Error fetching messages:', err.message);
    if (err.message.includes('Not a participant')) {
      return res.status(403).json({ error: err.message });
    }
    if (err.message.includes('not found') || err.message.includes('Conversation not found')) {
      return res.status(404).json({ error: err.message });
    }
    if (err.message.includes('Invalid')) {
      return res.status(400).json({ error: err.message });
    }
    res.status(500).json({ error: err.message || 'Failed to fetch messages' });
  }
});

// ── POST /api/conversations/:id/messages ──────────────────────────────────
// Send a message (REST fallback if socket isn't connected)
router.post('/conversations/:id/messages', authMiddleware, async (req, res) => {
  try {
    const { id } = req.params;
    const { content, type } = req.body;

    if (!content || !content.trim()) {
      return res.status(400).json({ error: 'content is required' });
    }

    const message = await messagingService.sendMessage(
      id,
      req.user.id,
      content.trim(),
      type || 'text'
    );

    res.json({ message });
  } catch (err) {
    console.error('Error sending message:', err.message);
    if (err.message.includes('block')) {
      return res.status(403).json({ error: err.message });
    }
    res.status(500).json({ error: 'Failed to send message' });
  }
});

// ── POST /api/block ───────────────────────────────────────────────────────
// Block a user
router.post('/block', authMiddleware, async (req, res) => {
  try {
    const { userId } = req.body;
    if (!userId) {
      return res.status(400).json({ error: 'userId is required' });
    }

    await messagingService.blockUser(req.user.id, userId);
    res.json({ success: true });
  } catch (err) {
    console.error('Error blocking user:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// ── DELETE /api/block/:userId ─────────────────────────────────────────────
// Unblock a user
router.delete('/block/:userId', authMiddleware, async (req, res) => {
  try {
    const { userId } = req.params;
    await messagingService.unblockUser(req.user.id, userId);
    res.json({ success: true });
  } catch (err) {
    console.error('Error unblocking user:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// ── POST /api/report ──────────────────────────────────────────────────────
// Report a user/message & trigger strike escalation
router.post('/report', authMiddleware, async (req, res) => {
  try {
    const { ModerationService } = require('../moderation/moderation.service');
    const { reportedUserId, reason, description, messageId, conversationId } = req.body;

    if (!reportedUserId || !reason) {
      return res.status(400).json({ error: 'reportedUserId and reason are required' });
    }

    const result = await ModerationService.fileReport(
      req.user.id,
      reportedUserId,
      reason,
      description || null,
      messageId || null,
      conversationId || null
    );

    res.json({ success: true, ...result });
  } catch (err) {
    console.error('Error reporting user:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// ── GET /api/presence ─────────────────────────────────────────────────────
// Query online status for one or more user IDs
router.get('/presence', authMiddleware, async (req, res) => {
  try {
    const { userIds } = req.query;
    if (!userIds) {
      return res.json({ presence: {} });
    }

    const ids = Array.isArray(userIds) ? userIds : userIds.split(',').map((id) => id.trim()).filter(Boolean);
    const { PresenceService } = require('../presence/presence.service');
    const { redis } = require('../../server');

    const presenceMap = await PresenceService.getPresenceBatch(redis, ids);
    res.json({ presence: presenceMap });
  } catch (err) {
    console.error('Error fetching presence:', err.message);
    res.status(500).json({ error: 'Failed to fetch presence' });
  }
});

module.exports = router;

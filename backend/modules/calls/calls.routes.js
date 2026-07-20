const express = require('express');
const router = express.Router();
const db = require('../../db');
const { authMiddleware } = require('../../middleware/auth.middleware');

/**
 * Endpoint: GET /api/calls/history
 * Returns the authenticated user's call history.
 * Retains exact same JSON format as previously returned by Supabase to avoid breaking client parser.
 */
router.get('/history', authMiddleware, async (req, res) => {
  const userId = req.user.id;

  try {
    const result = await db.query(
      `SELECT c.id, c.caller_id, c.matched_user_id, c.status, c.call_type, c.duration_seconds, c.started_at, c.ended_at,
              u1.full_name AS caller_name,
              u2.full_name AS matched_name
       FROM public.calls c
       LEFT JOIN public.users u1 ON c.caller_id = u1.id
       LEFT JOIN public.users u2 ON c.matched_user_id = u2.id
       WHERE c.caller_id = $1 OR c.matched_user_id = $1
       ORDER BY c.started_at DESC`,
      [userId]
    );

    // Map database rows to the nested format expected by Flutter CallLog.fromJson
    const formattedHistory = result.rows.map(row => ({
      id: row.id,
      caller_id: row.caller_id,
      matched_user_id: row.matched_user_id,
      status: row.status,
      call_type: row.call_type,
      duration_seconds: row.duration_seconds,
      started_at: row.started_at,
      caller: {
        id: row.caller_id,
        full_name: row.caller_name || 'User'
      },
      matched_user: {
        id: row.matched_user_id,
        full_name: row.matched_name || 'User'
      }
    }));

    res.json(formattedHistory);
  } catch (err) {
    console.error('Error fetching call history:', err.message);
    res.status(500).json({ error: 'Internal server error loading call history.' });
  }
});

module.exports = router;

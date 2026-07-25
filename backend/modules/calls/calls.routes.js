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
              u1.full_name AS caller_name, u1.gender AS caller_gender, u1.avatar_seed AS caller_avatar_seed, u1.avatar_style AS caller_avatar_style,
              u2.full_name AS matched_name, u2.gender AS matched_gender, u2.avatar_seed AS matched_avatar_seed, u2.avatar_style AS matched_avatar_style
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
        full_name: row.caller_name || 'User',
        gender: row.caller_gender,
        avatar_seed: row.caller_avatar_seed,
        avatar_style: row.caller_avatar_style || 'avataaars',
      },
      matched_user: {
        id: row.matched_user_id,
        full_name: row.matched_name || 'User',
        gender: row.matched_gender,
        avatar_seed: row.matched_avatar_seed,
        avatar_style: row.matched_avatar_style || 'avataaars',
      }
    }));

    res.json(formattedHistory);
  } catch (err) {
    console.error('Error fetching call history:', err.message);
    res.status(500).json({ error: 'Internal server error loading call history.' });
  }
});

const { userSockets } = require('../matchmaking/matchmaking.socket');

/**
 * Endpoint: GET /api/calls/matches
 * Returns a list of users matched with the current user.
 */
router.get('/matches', authMiddleware, async (req, res) => {
  const userId = req.user.id;

  try {
    const result = await db.query(
      `SELECT DISTINCT u.id, u.full_name, u.gender, u.avatar_seed, u.avatar_style,
              EXISTS(
                SELECT 1 FROM public.favorites f 
                WHERE f.user_id = $1 AND f.favorite_user_id = u.id
              ) AS is_favorite
       FROM public.users u
       JOIN public.calls c ON (c.caller_id = u.id OR c.matched_user_id = u.id)
       WHERE u.id != $1 AND (c.caller_id = $1 OR c.matched_user_id = $1) AND c.status = 'ended'
       ORDER BY u.full_name ASC`,
      [userId]
    );

    const matches = result.rows.map(row => ({
      id: row.id,
      fullName: row.full_name || 'User',
      gender: row.gender,
      avatarSeed: row.avatar_seed,
      avatarStyle: row.avatar_style || 'avataaars',
      isOnline: userSockets ? userSockets.has(row.id) : false,
      isFavorite: row.is_favorite
    }));

    res.json(matches);
  } catch (err) {
    console.error('Error fetching matches:', err.message);
    res.status(500).json({ error: 'Internal server error loading matches.' });
  }
});

/**
 * Endpoint: GET /api/calls/favorites
 * Returns the current user's favorited users.
 */
router.get('/favorites', authMiddleware, async (req, res) => {
  const userId = req.user.id;

  try {
    const result = await db.query(
      `SELECT u.id, u.full_name, u.gender, u.avatar_seed, u.avatar_style, true AS is_favorite
       FROM public.users u
       JOIN public.favorites f ON f.favorite_user_id = u.id
       WHERE f.user_id = $1
       ORDER BY f.created_at DESC`,
      [userId]
    );

    const favorites = result.rows.map(row => ({
      id: row.id,
      fullName: row.full_name || 'User',
      gender: row.gender,
      avatarSeed: row.avatar_seed,
      avatarStyle: row.avatar_style || 'avataaars',
      isOnline: userSockets ? userSockets.has(row.id) : false,
      isFavorite: true
    }));

    res.json(favorites);
  } catch (err) {
    console.error('Error fetching favorites:', err.message);
    res.status(500).json({ error: 'Internal server error loading favorites.' });
  }
});

/**
 * Endpoint: POST /api/calls/favorites
 * Adds a user to the current user's favorites.
 */
router.post('/favorites', authMiddleware, async (req, res) => {
  const userId = req.user.id;
  const { favoriteUserId } = req.body;

  if (!favoriteUserId) {
    return res.status(400).json({ error: 'favoriteUserId is required.' });
  }

  try {
    await db.query(
      `INSERT INTO public.favorites (user_id, favorite_user_id)
       VALUES ($1, $2)
       ON CONFLICT (user_id, favorite_user_id) DO NOTHING`,
      [userId, favoriteUserId]
    );

    res.json({ success: true });
  } catch (err) {
    console.error('Error adding favorite:', err.message);
    res.status(500).json({ error: 'Internal server error adding favorite.' });
  }
});

/**
 * Endpoint: DELETE /api/calls/favorites/:favoriteUserId
 * Removes a user from the current user's favorites.
 */
router.delete('/favorites/:favoriteUserId', authMiddleware, async (req, res) => {
  const userId = req.user.id;
  const { favoriteUserId } = req.params;

  try {
    await db.query(
      `DELETE FROM public.favorites
       WHERE user_id = $1 AND favorite_user_id = $2`,
      [userId, favoriteUserId]
    );

    res.json({ success: true });
  } catch (err) {
    console.error('Error removing favorite:', err.message);
    res.status(500).json({ error: 'Internal server error removing favorite.' });
  }
});

module.exports = router;

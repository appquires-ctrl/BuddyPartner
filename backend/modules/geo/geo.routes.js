'use strict';

const express = require('express');
const { authMiddleware } = require('../../middleware/auth.middleware');
const { geoService } = require('./geo.service');

const router = express.Router();

/**
 * GET /api/geo/cities
 * Returns a list of cities for the given country ISO code, filtered by an optional query.
 *
 * Query params:
 *   - country  {string}  ISO 3166-1 alpha-2 code (e.g. 'IN', 'US'). Defaults to user profile country.
 *   - q        {string}  Optional city search query (case-insensitive, min 1 char)
 *   - limit    {number}  Max results (default: 20, max: 50)
 *
 * Response: { cities: [{ city: string, state: string }] }
 */
router.get('/cities', authMiddleware, async (req, res) => {
  try {
    let { country, q, limit } = req.query;

    // Fallback: use the authenticated user's registered country if not provided
    if (!country) {
      const db = require('../../db');
      const userRes = await db.query(
        'SELECT country FROM public.users WHERE id = $1',
        [req.user.id]
      );
      country = userRes.rows[0]?.country || 'IN';
    }

    // Normalize inputs
    const iso = (country || 'IN').toUpperCase().replace(/[^A-Z]/g, '').slice(0, 2);
    const query = (q || '').trim().slice(0, 100); // safety cap
    const parsedLimit = Math.min(Math.max(parseInt(limit, 10) || 20, 1), 50);

    const cities = await geoService.searchCities({
      countryIso: iso,
      q: query,
      limit: parsedLimit,
    });

    return res.json({ cities });
  } catch (err) {
    console.error('[GeoRoutes] /cities error:', err.message);
    return res.status(500).json({ error: 'Failed to fetch city list' });
  }
});

/**
 * GET /api/geo/states
 * Returns all states/provinces for the given country ISO code.
 *
 * Query params:
 *   - country  {string}  ISO 3166-1 alpha-2 code (e.g. 'IN', 'US'). Defaults to user profile country.
 *
 * Response: { states: string[] }
 */
router.get('/states', authMiddleware, async (req, res) => {
  try {
    let { country } = req.query;

    if (!country) {
      const db = require('../../db');
      const userRes = await db.query(
        'SELECT country FROM public.users WHERE id = $1',
        [req.user.id]
      );
      country = userRes.rows[0]?.country || 'IN';
    }

    const iso = (country || 'IN').toUpperCase().replace(/[^A-Z]/g, '').slice(0, 2);
    const states = await geoService.getStates(iso);

    return res.json({ states });
  } catch (err) {
    console.error('[GeoRoutes] /states error:', err.message);
    return res.status(500).json({ error: 'Failed to fetch state list' });
  }
});

module.exports = router;

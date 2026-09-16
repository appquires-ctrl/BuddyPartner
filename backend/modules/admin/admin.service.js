const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const db = require('../../db');
const { cacheService } = require('../../services/cache.service');
const { callQuotaService } = require('../calls/call_quota.service');

class AdminService {
  /**
   * Auto-ensure admin_config table exists and insert default password if empty.
   * Default password in dev: admin123
   */
  async initAdminConfig() {
    try {
      await db.query(`
        CREATE TABLE IF NOT EXISTS public.admin_config (
          id INTEGER PRIMARY KEY DEFAULT 1,
          password_hash TEXT NOT NULL,
          CONSTRAINT single_row CHECK (id = 1)
        );
      `);

      const checkRes = await db.query('SELECT * FROM public.admin_config WHERE id = 1');
      if (checkRes.rows.length === 0) {
        const defaultHash = bcrypt.hashSync('admin123', 10);
        await db.query(
          'INSERT INTO public.admin_config (id, password_hash) VALUES (1, $1) ON CONFLICT (id) DO NOTHING',
          [defaultHash]
        );
        console.log('✅ Admin config initialized with default hash for "admin123".');
      } else {
        console.log('✅ Admin config table verified.');
      }
    } catch (err) {
      console.error('❌ Failed to initialize admin_config table:', err.message);
    }
  }

  /**
   * Verify password against bcrypt hash in admin_config.
   * @param {string} password
   * @returns {Promise<boolean>}
   */
  async verifyPassword(password) {
    if (!password || typeof password !== 'string') return false;
    try {
      const res = await db.query('SELECT password_hash FROM public.admin_config WHERE id = 1');
      if (res.rows.length === 0) return false;

      const storedHash = res.rows[0].password_hash;
      return bcrypt.compareSync(password, storedHash);
    } catch (err) {
      console.error('Error verifying admin password:', err.message);
      return false;
    }
  }

  /**
   * High-level platform statistics for the Admin Dashboard.
   */
  async getDashboardStats() {
    try {
      const usersRes = await db.query(`
        SELECT 
          COUNT(*)::int AS total_users,
          COUNT(*) FILTER (WHERE LOWER(gender) = 'male')::int AS male_users,
          COUNT(*) FILTER (WHERE LOWER(gender) = 'female')::int AS female_users
        FROM public.users
      `);

      const withdrawalRes = await db.query(`
        SELECT COUNT(*)::int AS pending_withdrawals
        FROM public.withdrawals
        WHERE status = 'pending'
      `).catch(() => ({ rows: [{ pending_withdrawals: 0 }] }));

      const reportsRes = await db.query(`
        SELECT 
          COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '24 hours')::int AS reports_today,
          COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '7 days')::int AS reports_week
        FROM public.reports
      `).catch(() => ({ rows: [{ reports_today: 0, reports_week: 0 }] }));

      const coinsRes = await db.query(`
        SELECT COALESCE(SUM(spendable_delta), 0)::int AS total_recharged
        FROM public.wallet_transactions
        WHERE reason IN ('recharge', 'iap_purchase', 'razorpay_purchase')
      `).catch(() => ({ rows: [{ total_recharged: 0 }] }));

      const payoutsRes = await db.query(`
        SELECT COALESCE(SUM(amount), 0)::int AS total_payouts
        FROM public.withdrawals
        WHERE status IN ('approved', 'paid')
      `).catch(() => ({ rows: [{ total_payouts: 0 }] }));

      const u = usersRes.rows[0] || {};
      const w = withdrawalRes.rows[0] || {};
      const r = reportsRes.rows[0] || {};
      const c = coinsRes.rows[0] || {};
      const p = payoutsRes.rows[0] || {};

      return {
        totalUsers: u.total_users || 0,
        maleUsers: u.male_users || 0,
        femaleUsers: u.female_users || 0,
        pendingWithdrawals: w.pending_withdrawals || 0,
        reportsToday: r.reports_today || 0,
        reportsThisWeek: r.reports_week || 0,
        totalCoinsRecharged: c.total_recharged || 0,
        totalPayoutsPaidOut: p.total_payouts || 0,
      };
    } catch (err) {
      console.error('❌ Error fetching admin dashboard stats:', err.message);
      throw err;
    }
  }

  /**
   * Paginated, searchable, filterable list of users with dual-balance breakdown.
   */
  async getUsers({ search = '', gender = 'all', isBanned = 'all', page = 1, limit = 20 }) {
    try {
      const offset = (page - 1) * limit;
      const conditions = [];
      const params = [];

      if (search) {
        params.push(`%${search.toLowerCase()}%`);
        const idx = params.length;
        conditions.push(`(LOWER(u.full_name) LIKE $${idx} OR u.phone_number LIKE $${idx} OR LOWER(u.user_name) LIKE $${idx})`);
      }

      if (gender !== 'all') {
        params.push(gender.toLowerCase());
        conditions.push(`LOWER(u.gender) = $${params.length}`);
      }

      if (isBanned !== 'all') {
        const bannedBool = isBanned === 'true';
        params.push(bannedBool);
        conditions.push(`COALESCE(u.is_banned, FALSE) = $${params.length}`);
      }

      const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

      const countSql = `SELECT COUNT(*)::int AS total FROM public.users u ${whereClause}`;
      const countRes = await db.query(countSql, params);
      const total = countRes.rows[0]?.total || 0;

      params.push(limit);
      const limitIdx = params.length;
      params.push(offset);
      const offsetIdx = params.length;
      const currentYearMonth = callQuotaService.getCurrentYearMonth();
      params.push(currentYearMonth);
      const ymIdx = params.length;

      const dataSql = `
        SELECT 
          u.id, 
          COALESCE(u.full_name, 'User') AS name, 
          COALESCE(u.phone_number, '') AS phone, 
          u.gender, 
          COALESCE(u.is_banned, FALSE) AS is_banned, 
          COALESCE(u.strike_count, 0) AS strike_count,
          COALESCE(u.created_at, NOW()) AS signup_date,
          COALESCE(w.spendable_balance, 0)::int AS spendable_balance,
          COALESCE(w.earned_balance, 0)::int AS earned_balance,
          (COALESCE(w.spendable_balance, 0) + COALESCE(w.earned_balance, 0))::int AS coin_balance,
          COALESCE(q.audio_seconds, 0)::int AS audio_seconds,
          COALESCE(q.video_seconds, 0)::int AS video_seconds,
          (COALESCE(q.audio_seconds, 0) / 60)::int AS audio_minutes,
          (COALESCE(q.video_seconds, 0) / 60)::int AS video_minutes,
          sub.expires_at AS subscription_expires_at,
          CASE WHEN sub.expires_at > NOW() THEN TRUE ELSE FALSE END AS is_subscribed,
          (SELECT COUNT(*)::int FROM public.reports r WHERE r.reported_user_id = u.id) AS report_count
        FROM public.users u
        LEFT JOIN public.wallets w ON w.user_id = u.id
        LEFT JOIN public.user_monthly_call_usage q ON q.user_id = u.id AND q.year_month = $${ymIdx}
        LEFT JOIN LATERAL (
          SELECT expires_at
          FROM public.subscriptions
          WHERE user_id = u.id AND expires_at > NOW()
          ORDER BY expires_at DESC
          LIMIT 1
        ) sub ON true
        ${whereClause}
        ORDER BY u.created_at DESC NULLS LAST
        LIMIT $${limitIdx} OFFSET $${offsetIdx}
      `;

      const dataRes = await db.query(dataSql, params);

      return {
        users: dataRes.rows,
        total,
        page: Number(page),
        totalPages: Math.ceil(total / limit) || 1,
      };
    } catch (err) {
      console.error('❌ Error fetching users for admin:', err.message);
      throw err;
    }
  }

  /**
   * Detailed info for a single user.
   */
  async getUserDetail(userId) {
    try {
      const userRes = await db.query(
        `SELECT id, COALESCE(full_name, 'User') AS name, COALESCE(phone_number, '') AS phone, gender, COALESCE(is_banned, FALSE) AS is_banned, COALESCE(strike_count, 0) AS strike_count, is_telecaller, created_at FROM public.users WHERE id = $1`,
        [userId]
      );
      if (userRes.rows.length === 0) return null;

      const user = userRes.rows[0];

      // Wallet dual balances
      const walletRes = await db.query(
        'SELECT spendable_balance, earned_balance FROM public.wallets WHERE user_id = $1',
        [userId]
      ).catch(() => ({ rows: [] }));

      const spendableBalance = Number(walletRes.rows[0]?.spendable_balance || 0);
      const earnedBalance = Number(walletRes.rows[0]?.earned_balance || 0);
      const coinBalance = spendableBalance + earnedBalance;

      // Active & recent subscriptions
      const subRes = await db.query(
        `SELECT id, plan_duration_days, amount_paid, started_at, expires_at, payment_reference, created_at,
                (expires_at > NOW()) AS is_active
         FROM public.subscriptions
         WHERE user_id = $1
         ORDER BY created_at DESC
         LIMIT 5`,
        [userId]
      ).catch(() => ({ rows: [] }));

      const activeSub = subRes.rows.find((s) => s.is_active) || null;

      // Reports filed against user
      const reportsRes = await db.query(
        `SELECT r.id, r.reason, r.description, r.created_at, COALESCE(u.full_name, 'Anonymous') AS reporter_name
         FROM public.reports r
         LEFT JOIN public.users u ON r.reporter_id = u.id
         WHERE r.reported_user_id = $1
         ORDER BY r.created_at DESC`,
        [userId]
      ).catch(() => ({ rows: [] }));

      // Fetch real-time and monthly call usage
      const callUsage = await callQuotaService.getUsage(userId);

      return {
        ...user,
        spendableBalance,
        earnedBalance,
        coinBalance,
        activeSubscription: activeSub,
        subscriptionHistory: subRes.rows,
        reports: reportsRes.rows,
        callUsage,
      };
    } catch (err) {
      console.error('❌ Error fetching user details for admin:', err.message);
      throw err;
    }
  }

  /**
   * Get detailed live and historical call usage for a user.
   */
  async getUserCallUsage(userId) {
    const liveUsage = await callQuotaService.getUsage(userId);
    const historyRes = await db.query(
      `SELECT year_month, audio_seconds, video_seconds, audio_call_count, video_call_count, updated_at
       FROM public.user_monthly_call_usage
       WHERE user_id = $1
       ORDER BY year_month DESC
       LIMIT 12`,
      [userId]
    ).catch(() => ({ rows: [] }));

    return {
      liveUsage,
      history: historyRes.rows.map((r) => ({
        ...r,
        audioMinutes: Math.floor(r.audio_seconds / 60),
        videoMinutes: Math.floor(r.video_seconds / 60),
      })),
    };
  }

  /**
   * Reset a user's monthly call quota.
   */
  async resetUserCallQuota(userId) {
    return await callQuotaService.resetUserQuota(userId);
  }

  /**
   * Ban or unban a user.
   */
  async setBanStatus(userId, isBanned, reason = '') {
    try {
      const res = await db.query(
        `UPDATE public.users SET is_banned = $1 WHERE id = $2 RETURNING id, full_name, is_banned`,
        [isBanned, userId]
      );
      if (res.rows.length === 0) throw new Error('User not found');
      return res.rows[0];
    } catch (err) {
      console.error(`❌ Error setting ban status for user ${userId}:`, err.message);
      throw err;
    }
  }

  /**
   * Get withdrawal requests table with earned balance provenance.
   */
  async getWithdrawals({ status = 'all', page = 1, limit = 20 }) {
    try {
      const offset = (page - 1) * limit;
      const params = [];
      let whereClause = '';

      if (status !== 'all') {
        params.push(status);
        whereClause = `WHERE w.status = $1`;
      }

      const countSql = `SELECT COUNT(*)::int AS total FROM public.withdrawals w ${whereClause}`;
      const countRes = await db.query(countSql, params).catch(() => ({ rows: [{ total: 0 }] }));
      const total = countRes.rows[0]?.total || 0;

      params.push(limit);
      const limitIdx = params.length;
      params.push(offset);
      const offsetIdx = params.length;

      const sql = `
        SELECT 
          w.id, w.user_id, w.amount, w.rupee_amount, w.status, w.payout_method, w.payout_details, w.admin_note, w.requested_at, w.processed_at,
          COALESCE(u.full_name, 'Creator') AS user_name, COALESCE(u.phone_number, '') AS user_phone,
          COALESCE(wl.earned_balance, 0)::int AS current_earned_balance,
          COALESCE(wl.spendable_balance, 0)::int AS current_spendable_balance
        FROM public.withdrawals w
        LEFT JOIN public.users u ON w.user_id = u.id
        LEFT JOIN public.wallets wl ON w.user_id = wl.user_id
        ${whereClause}
        ORDER BY w.requested_at DESC
        LIMIT $${limitIdx} OFFSET $${offsetIdx}
      `;

      const dataRes = await db.query(sql, params).catch(() => ({ rows: [] }));

      return {
        withdrawals: dataRes.rows,
        total,
        page: Number(page),
        totalPages: Math.ceil(total / limit) || 1,
      };
    } catch (err) {
      console.error('❌ Error fetching withdrawal requests for admin:', err.message);
      throw err;
    }
  }

  /**
   * Update status of withdrawal request (pending, approved, rejected, paid).
   * On rejection: atomically credits earned_balance back and writes a compensating ledger row.
   */
  async updateWithdrawalStatus(withdrawalId, status, adminNote = null) {
    const validStatuses = ['pending', 'approved', 'rejected', 'paid'];
    if (!validStatuses.includes(status)) {
      throw new Error(`Invalid status. Must be one of: ${validStatuses.join(', ')}`);
    }

    const client = await db.pool.connect();
    try {
      await client.query('BEGIN');

      const existingRes = await client.query(
        'SELECT * FROM public.withdrawals WHERE id = $1 FOR UPDATE',
        [withdrawalId]
      );
      if (existingRes.rows.length === 0) {
        await client.query('ROLLBACK');
        throw new Error('Withdrawal request not found');
      }

      const withdrawal = existingRes.rows[0];

      if (withdrawal.status === status) {
        await client.query('COMMIT');
        return withdrawal;
      }

      // If rejecting a pending withdrawal, credit back the earned_balance
      if (status === 'rejected' && withdrawal.status === 'pending') {
        const refundAmount = Number(withdrawal.amount);
        const userId = withdrawal.user_id;

        await client.query(
          `UPDATE public.wallets
           SET earned_balance = earned_balance + $1::bigint,
               updated_at = NOW()
           WHERE user_id = $2`,
          [refundAmount, userId]
        );

        const refKey = `refund_${withdrawal.id}`;
        await client.query(
          `INSERT INTO public.wallet_transactions (
             user_id, spendable_delta, earned_delta, idempotency_key, reason, reference_id
           ) VALUES ($1, 0, $2, $3, 'withdrawal_reject_refund', $4)`,
          [userId, refundAmount, refKey, withdrawal.id]
        );

        await cacheService.invalidate(`user:balance:${userId}`).catch(() => {});
        console.log(`↩️ [Admin] Refunded ${refundAmount} earned coins to user ${userId} for rejected withdrawal ${withdrawalId}`);
      }

      const res = await client.query(
        `UPDATE public.withdrawals
         SET status = $1, admin_note = COALESCE($2, admin_note), processed_at = NOW()
         WHERE id = $3
         RETURNING *`,
        [status, adminNote, withdrawalId]
      );

      await client.query('COMMIT');
      return res.rows[0];
    } catch (err) {
      await client.query('ROLLBACK').catch(() => {});
      console.error(`❌ Error updating withdrawal status ${withdrawalId}:`, err.message);
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * Cancel an open or accepted Buddy request by admin. Strictly no refunds.
   */
  async cancelBuddyRequest(requestId, adminId = null, reason = 'admin_action') {
    const { buddyService } = require('../buddy/buddy.service');
    return await buddyService.adminCancelRequest(requestId, adminId, reason);
  }

  /**
   * Read-only transactions log.
   */
  async getTransactions({ page = 1, limit = 20 }) {
    try {
      const offset = (page - 1) * limit;

      const countRes = await db.query(`SELECT COUNT(*)::int AS total FROM public.wallet_transactions`).catch(() => ({ rows: [{ total: 0 }] }));
      const total = countRes.rows[0]?.total || 0;

      const res = await db.query(`
        SELECT 
          t.id, t.user_id, t.spendable_delta, t.earned_delta,
          (t.spendable_delta + t.earned_delta) AS amount,
          CASE WHEN (t.spendable_delta + t.earned_delta) >= 0 THEN 'credit' ELSE 'debit' END AS type,
          t.reason, t.idempotency_key, t.reference_id, t.created_at,
          COALESCE(u.full_name, 'User') AS user_name, COALESCE(u.phone_number, '') AS user_phone
        FROM public.wallet_transactions t
        LEFT JOIN public.users u ON t.user_id = u.id
        ORDER BY t.created_at DESC
        LIMIT $1 OFFSET $2
      `, [limit, offset]).catch(() => ({ rows: [] }));

      return {
        transactions: res.rows,
        total,
        page: Number(page),
        totalPages: Math.ceil(total / limit) || 1,
      };
    } catch (err) {
      console.error('❌ Error fetching transactions for admin:', err.message);
      throw err;
    }
  }

  /**
   * Directly grant promotional coins to a user from admin.
   * Credits spendable_balance (non-withdrawable).
   */
  async giveCoins(userId, amount, reason = 'admin_grant') {
    const coinAmount = parseInt(amount, 10);
    if (isNaN(coinAmount) || coinAmount <= 0) {
      const err = new Error('Amount must be a positive integer');
      err.status = 400;
      throw err;
    }

    const userCheck = await db.query('SELECT id, full_name FROM public.users WHERE id = $1', [userId]);
    if (userCheck.rows.length === 0) {
      const err = new Error('User not found');
      err.status = 404;
      throw err;
    }

    const refId = `ADMIN_GIFT_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`;
    const client = await db.pool.connect();
    try {
      await client.query('BEGIN');

      const walletRes = await client.query(
        `INSERT INTO public.wallets (user_id, spendable_balance, earned_balance)
         VALUES ($1, $2, 0)
         ON CONFLICT (user_id)
         DO UPDATE SET 
           spendable_balance = public.wallets.spendable_balance + $2,
           updated_at = NOW()
         RETURNING spendable_balance, earned_balance`,
        [userId, coinAmount]
      );

      const sBal = Number(walletRes.rows[0].spendable_balance);
      const eBal = Number(walletRes.rows[0].earned_balance);

      await client.query(
        `INSERT INTO public.wallet_transactions (user_id, spendable_delta, earned_delta, idempotency_key, reason, reference_id)
         VALUES ($1, $2, 0, $3, 'admin_grant', $3)`,
        [userId, coinAmount, refId]
      );

      await client.query('COMMIT');
      await cacheService.invalidate(`user:balance:${userId}`).catch(() => {});

      return {
        userId,
        spendableBalance: sBal,
        earnedBalance: eBal,
        newBalance: sBal + eBal,
        creditedAmount: coinAmount,
        reason,
      };
    } catch (err) {
      await client.query('ROLLBACK').catch(() => {});
      console.error(`❌ Error granting coins to user ${userId}:`, err.message);
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * Directly grant VIP subscription to a user for specified duration (default 365 days).
   * @param {string} userId
   * @param {number} durationDays
   * @param {string} paymentReference
   */
  async giveSubscription(userId, durationDays = 365, paymentReference = 'ADMIN_GRANT') {
    const days = parseInt(durationDays, 10);
    if (isNaN(days) || days <= 0) {
      const err = new Error('Duration in days must be a positive integer');
      err.status = 400;
      throw err;
    }

    const userCheck = await db.query('SELECT id, full_name FROM public.users WHERE id = $1', [userId]);
    if (userCheck.rows.length === 0) {
      const err = new Error('User not found');
      err.status = 404;
      throw err;
    }

    // Check if user currently has an active subscription
    const activeRes = await db.query(
      `SELECT expires_at FROM public.subscriptions
       WHERE user_id = $1 AND expires_at > NOW()
       ORDER BY expires_at DESC
       LIMIT 1`,
      [userId]
    );

    let baseTime = Date.now();
    if (activeRes.rows.length > 0 && activeRes.rows[0].expires_at) {
      const currentExpiry = new Date(activeRes.rows[0].expires_at).getTime();
      if (currentExpiry > baseTime) {
        baseTime = currentExpiry;
      }
    }

    const expiresAt = new Date(baseTime + days * 24 * 60 * 60 * 1000);

    const insertRes = await db.query(
      `INSERT INTO public.subscriptions (user_id, plan_duration_days, amount_paid, started_at, expires_at, payment_reference)
       VALUES ($1, $2, 0, NOW(), $3, $4)
       RETURNING id, user_id, plan_duration_days, amount_paid, started_at, expires_at, payment_reference, created_at`,
      [userId, days, expiresAt.toISOString(), paymentReference]
    );

    await cacheService.invalidate(`subscription_status:${userId}`).catch(() => {});
    await cacheService.invalidate(`sub:active:${userId}`).catch(() => {});

    return {
      userId,
      subscription: insertRes.rows[0],
      expiresAt: expiresAt.toISOString(),
      durationDays: days,
    };
  }

  async grantSubscription(userId, planDurationDays = 365, reason = 'admin_gift') {
    return this.giveSubscription(userId, planDurationDays, reason);
  }
}

module.exports = new AdminService();

const db = require('../../db');
const bcrypt = require('bcryptjs');
const { cacheService } = require('../../services/cache.service');

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
   * Fetch aggregated dashboard statistics.
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
        FROM public.withdrawal_requests
        WHERE status = 'pending'
      `).catch(() => ({ rows: [{ pending_withdrawals: 0 }] }));

      const reportsRes = await db.query(`
        SELECT 
          COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '24 hours')::int AS reports_today,
          COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '7 days')::int AS reports_week
        FROM public.reports
      `).catch(() => ({ rows: [{ reports_today: 0, reports_week: 0 }] }));

      const coinsRes = await db.query(`
        SELECT COALESCE(SUM(amount), 0)::int AS total_recharged
        FROM public.wallet_transactions
        WHERE type = 'credit' AND reason LIKE '%recharge%'
      `).catch(() => ({ rows: [{ total_recharged: 0 }] }));

      const rosesRes = await db.query(`
        SELECT COALESCE(SUM(rose_amount), 0)::int AS total_roses_paid
        FROM public.withdrawal_requests
        WHERE status IN ('approved', 'paid')
      `).catch(() => ({ rows: [{ total_roses_paid: 0 }] }));

      const u = usersRes.rows[0] || {};
      const w = withdrawalRes.rows[0] || {};
      const r = reportsRes.rows[0] || {};
      const c = coinsRes.rows[0] || {};
      const ro = rosesRes.rows[0] || {};

      return {
        totalUsers: u.total_users || 0,
        maleUsers: u.male_users || 0,
        femaleUsers: u.female_users || 0,
        pendingWithdrawals: w.pending_withdrawals || 0,
        reportsToday: r.reports_today || 0,
        reportsThisWeek: r.reports_week || 0,
        totalCoinsRecharged: c.total_recharged || 0,
        totalRosesPaidOut: ro.total_roses_paid || 0,
      };
    } catch (err) {
      console.error('Error fetching admin dashboard stats:', err.message);
      throw err;
    }
  }

  /**
   * Searchable and paginated user management table.
   */
  async getUsers({ search = '', gender = 'all', isBanned = 'all', page = 1, limit = 20 }) {
    try {
      const offset = (page - 1) * limit;
      const params = [];
      const conditions = [];

      if (search.trim()) {
        params.push(`%${search.trim().toLowerCase()}%`);
        conditions.push(`(LOWER(COALESCE(u.full_name, '')) LIKE $${params.length} OR LOWER(COALESCE(u.phone_number, '')) LIKE $${params.length})`);
      }

      if (gender !== 'all') {
        params.push(gender.toLowerCase());
        conditions.push(`LOWER(u.gender) = $${params.length}`);
      }

      if (isBanned === 'true' || isBanned === 'banned') {
        conditions.push(`u.is_banned = TRUE`);
      } else if (isBanned === 'false' || isBanned === 'active') {
        conditions.push(`(u.is_banned IS FALSE OR u.is_banned IS NULL)`);
      }

      const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

      const countSql = `SELECT COUNT(*)::int AS total FROM public.users u ${whereClause}`;
      const countRes = await db.query(countSql, params);
      const total = countRes.rows[0]?.total || 0;

      params.push(limit);
      const limitIdx = params.length;
      params.push(offset);
      const offsetIdx = params.length;

      const dataSql = `
        SELECT 
          u.id, 
          COALESCE(u.full_name, 'User') AS name, 
          COALESCE(u.phone_number, '') AS phone, 
          u.gender, 
          COALESCE(u.is_banned, FALSE) AS is_banned, 
          COALESCE(u.strike_count, 0) AS strike_count,
          COALESCE(u.created_at, NOW()) AS signup_date,
          COALESCE(w.balance, 0)::int AS coin_balance,
          sub.expires_at AS subscription_expires_at,
          CASE WHEN sub.expires_at > NOW() THEN TRUE ELSE FALSE END AS is_subscribed,
          (SELECT COUNT(*)::int FROM public.reports r WHERE r.reported_user_id = u.id) AS report_count
        FROM public.users u
        LEFT JOIN public.wallets w ON w.user_id = u.id
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
      console.error('Error fetching users for admin:', err.message);
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

      // Wallet balance
      const walletRes = await db.query(
        'SELECT balance FROM public.wallets WHERE user_id = $1',
        [userId]
      ).catch(() => ({ rows: [] }));
      const coinBalance = walletRes.rows[0]?.balance || 0;

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

      // Call history summary
      const callsRes = await db.query(
        `SELECT COUNT(*)::int AS total_calls, COALESCE(SUM(duration_seconds), 0)::int AS total_duration
         FROM public.call_history
         WHERE caller_id = $1 OR callee_id = $1`,
        [userId]
      ).catch(() => ({ rows: [{ total_calls: 0, total_duration: 0 }] }));

      const callStats = callsRes.rows[0] || { total_calls: 0, total_duration: 0 };

      return {
        ...user,
        coinBalance,
        activeSubscription: activeSub,
        subscriptionHistory: subRes.rows,
        reports: reportsRes.rows,
        callStats,
      };
    } catch (err) {
      console.error(`Error fetching detail for user ${userId}:`, err.message);
      throw err;
    }
  }

  /**
   * Set user ban status.
   */
  async setBanStatus(userId, isBanned) {
    try {
      const res = await db.query(
        `UPDATE public.users SET is_banned = $1 WHERE id = $2 RETURNING id, full_name AS name, is_banned`,
        [Boolean(isBanned), userId]
      );
      if (res.rows.length === 0) {
        throw new Error('User not found');
      }
      return res.rows[0];
    } catch (err) {
      console.error(`Error toggling ban for user ${userId}:`, err.message);
      throw err;
    }
  }

  /**
   * Get filed reports queue.
   */
  async getReports({ page = 1, limit = 20 }) {
    try {
      const offset = (page - 1) * limit;
      const countRes = await db.query(`SELECT COUNT(*)::int AS total FROM public.reports`).catch(() => ({ rows: [{ total: 0 }] }));
      const total = countRes.rows[0]?.total || 0;

      const reportsRes = await db.query(`
        SELECT 
          r.id, r.reason, r.description, r.created_at,
          r.reporter_id, COALESCE(u_rep.full_name, 'Anonymous') AS reporter_name, COALESCE(u_rep.phone_number, '') AS reporter_phone,
          r.reported_user_id, COALESCE(u_target.full_name, 'User') AS reported_name, COALESCE(u_target.phone_number, '') AS reported_phone, COALESCE(u_target.is_banned, FALSE) AS reported_is_banned
        FROM public.reports r
        LEFT JOIN public.users u_rep ON r.reporter_id = u_rep.id
        LEFT JOIN public.users u_target ON r.reported_user_id = u_target.id
        ORDER BY r.created_at DESC
        LIMIT $1 OFFSET $2
      `, [limit, offset]).catch(() => ({ rows: [] }));

      return {
        reports: reportsRes.rows,
        total,
        page: Number(page),
        totalPages: Math.ceil(total / limit) || 1,
      };
    } catch (err) {
      console.error('Error fetching reports for admin:', err.message);
      throw err;
    }
  }

  /**
   * Get withdrawal requests table.
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

      const countSql = `SELECT COUNT(*)::int AS total FROM public.withdrawal_requests w ${whereClause}`;
      const countRes = await db.query(countSql, params).catch(() => ({ rows: [{ total: 0 }] }));
      const total = countRes.rows[0]?.total || 0;

      params.push(limit);
      const limitIdx = params.length;
      params.push(offset);
      const offsetIdx = params.length;

      const sql = `
        SELECT 
          w.id, w.user_id, w.rose_amount, w.rupee_amount, w.status, w.requested_at, w.processed_at,
          COALESCE(u.full_name, 'Creator') AS user_name, COALESCE(u.phone_number, '') AS user_phone
        FROM public.withdrawal_requests w
        LEFT JOIN public.users u ON w.user_id = u.id
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
      console.error('Error fetching withdrawal requests for admin:', err.message);
      throw err;
    }
  }

  /**
   * Update status of withdrawal request (pending, approved, rejected, paid).
   */
  async updateWithdrawalStatus(withdrawalId, status) {
    const validStatuses = ['pending', 'approved', 'rejected', 'paid'];
    if (!validStatuses.includes(status)) {
      throw new Error(`Invalid status. Must be one of: ${validStatuses.join(', ')}`);
    }

    try {
      const res = await db.query(`
        UPDATE public.withdrawal_requests
        SET status = $1, processed_at = NOW()
        WHERE id = $2
        RETURNING *
      `, [status, withdrawalId]);

      if (res.rows.length === 0) {
        throw new Error('Withdrawal request not found');
      }

      return res.rows[0];
    } catch (err) {
      console.error(`Error updating withdrawal status ${withdrawalId}:`, err.message);
      throw err;
    }
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
          t.id, t.user_id, t.amount, t.type, t.reason, t.created_at,
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
      console.error('Error fetching transactions for admin:', err.message);
      throw err;
    }
  }

  /**
   * Directly grant coins to a user from admin.
   * @param {string} userId
   * @param {number} amount
   * @param {string} reason
   */
  async giveCoins(userId, amount, reason = 'admin_gift') {
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

    const client = await db.pool.connect();
    try {
      await client.query('BEGIN');

      const walletRes = await client.query(
        `INSERT INTO public.wallets (user_id, balance)
         VALUES ($1, $2)
         ON CONFLICT (user_id)
         DO UPDATE SET balance = public.wallets.balance + $2
         RETURNING balance`,
        [userId, coinAmount]
      );
      const newBalance = walletRes.rows[0].balance;

      const refId = `ADMIN_GIFT_${Date.now()}`;
      await client.query(
        `INSERT INTO public.wallet_transactions (user_id, amount, type, reason, reference_id)
         VALUES ($1, $2, 'credit', $3, $4)`,
        [userId, coinAmount, reason, refId]
      );

      await client.query('COMMIT');

      // Invalidate Redis/memory balance cache
      await cacheService.invalidate(`user:balance:${userId}`);

      return {
        userId,
        newBalance,
        creditedAmount: coinAmount,
        reason,
      };
    } catch (err) {
      await client.query('ROLLBACK');
      console.error(`Error granting coins to user ${userId}:`, err.message);
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

    // Invalidate Redis/memory subscription cache
    await cacheService.invalidate(`subscription_status:${userId}`);

    return {
      userId,
      subscription: insertRes.rows[0],
      expiresAt: expiresAt.toISOString(),
      durationDays: days,
    };
  }
}

module.exports = new AdminService();


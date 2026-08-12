# Replace Report Escalation Logic — 3 Distinct Reporters = Permanent Ban

Paste into your code-generation tool. **This replaces the previous escalation rule entirely** (1st report → 24h suspension, 2nd report → 2-day suspension, 3rd report → ban). The new rule is simpler: no timed suspensions at all — a user is permanently banned the moment **3 different people** have reported them.

---

## 1. New rule (exact)

- A ban is triggered when a user has been reported by **3 distinct reporters** — not 3 reports total. The same person reporting the same user multiple times only ever counts once toward this threshold.
- There is no 24-hour or 2-day intermediate suspension anymore — remove that logic. Reports 1 and 2 (from different people) don't restrict the account at all; the 3rd distinct reporter triggers an immediate permanent ban.
- Once banned, the account stays banned until an admin manually reverses it directly in the Neon database — there is no in-app appeal, countdown, or automatic reactivation. (See Section 4 for the one exception: the user-facing message promises reactivation "within 24 hours" after an apology email — that's a manual human process on your end, not something the app automates.)

---

## 2. Database changes

```sql
-- Remove the old escalation columns' meaning — keep is_banned, drop suspension timing logic
-- (leave suspended_until column in place if you want to preserve historical data, just stop writing to it)

-- Nothing new needed structurally if `reports` already stores reporter_id + reported_user_id + created_at.
-- Confirm your existing `reports` table has both of these columns distinctly — the distinct-reporter count
-- depends on being able to COUNT(DISTINCT reporter_id) per reported user.
```

---

## 3. Backend changes — `moderation.service.js` (replace, not extend)

- Remove `applyStrikeIfEligible`'s tiered 24h/48h/ban logic entirely
- New logic in `fileReport(reporterId, reportedUserId, reason)`:
  1. Insert the report as before (if the same reporter has already reported this user before, still log it, but it won't count as a *new* distinct reporter)
  2. After inserting, run: `SELECT COUNT(DISTINCT reporter_id) FROM reports WHERE reported_user_id = $1` for that user
  3. If the distinct count reaches **3**, set `is_banned = true` immediately — no suspension period, straight to permanent ban
- Remove any code path that sets/checks `suspended_until` for blocking purposes — `auth.middleware.js` should now only check `is_banned`, not a suspension timestamp
- `isUserBlocked(userId)` simplifies to just returning `is_banned`

---

## 4. Flutter — Banned account screen

Replace the existing `SuspendedScreen`/`BannedScreen` split with a single banned-state screen, shown when the user hits the `is_banned` rejection on login/app open:

- Message: something like *"Your account has been blocked due to multiple reports from other users."*
- Instructions: *"If you believe this was a mistake, please send an apology/appeal email to **[support@yourapp.com]** along with your registered mobile number, explaining your situation. Accounts are typically reviewed and reactivated within 24 hours."*
- Show the actual support email clearly (use a real placeholder like `support@buddypartner.com` — swap in your real support address before launch)
- No countdown timer (unlike the old suspension screen) — this is a hard block pending a manual human review, not a timed auto-unlock
- Remove the old `SuspendedScreen` entirely (no more 24h/48h timed state exists anymore) — keep only this one banned-state screen

---

## 5. Admin unban process (manual, for now)

Since there's no admin dashboard yet, unbanning is a **direct Neon database operation** you'll run by hand when someone sends a genuine apology email:

```sql
UPDATE public.users
SET is_banned = false
WHERE id = '<the user''s Firebase UID>';

DELETE FROM public.reports
WHERE reported_user_id = '<the user''s Firebase UID>';
```

**Decision: clear report history on unban.** When manually unbanning someone, also delete their prior reports so old reports don't immediately re-trigger the 3-distinct-reporter ban the moment anything re-checks the count. Run both statements together as one unban action:

```sql
UPDATE public.users
SET is_banned = false
WHERE id = '<the user''s Firebase UID>';

DELETE FROM public.reports
WHERE reported_user_id = '<the user''s Firebase UID>';
```

---

## 6. Things to verify before shipping this pass

- The same person reporting the same user 3 separate times does **not** trigger a ban — only 3 genuinely different reporter IDs do. Test this specifically, since it's the one detail most likely to be implemented wrong (a naive `COUNT(*)` instead of `COUNT(DISTINCT reporter_id)`)
- Confirm the old suspension logic is fully removed, not just unreachable dead code — check `auth.middleware.js` no longer references `suspended_until` for blocking decisions
- Confirm the banned screen shows correctly and permanently (no countdown, no auto-expiry) until you manually clear `is_banned` in the database
- Test the actual manual unban SQL against a real banned test account and confirm they can log in normally afterward

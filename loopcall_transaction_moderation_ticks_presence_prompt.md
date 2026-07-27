# Implement: Transaction History, Block/Report Escalation, Message Ticks, Online Presence Audit

Paste into your code-generation tool. This covers four separate features — treat each section independently, they touch different parts of the app.

---

## Part 1 — Transaction History

### Goal
A screen where any user can see their own past coin (boys) or rose (girls) transactions — recharge, call spend, call earnings, withdrawal requests — in one chronological list.

### Backend
- `GET /wallet/transactions?cursor=&limit=` (boys) — reads from `wallet_transactions`, cursor-paginated by `created_at`, scoped to the requesting user's own ID only (verified from the auth token — no other user's data reachable)
- `GET /roses/transactions?cursor=&limit=` (girls) — same pattern, reads from `rose_transactions`
- Each row returned should include: type (credit/debit), amount, reason (human-readable — map `call_minute`, `signup_bonus`, `recharge`, `withdrawal_request` etc. to friendly labels server-side or provide a mapping the client can use), timestamp

### Flutter
- New `features/wallet/presentation/pages/transaction_history_page.dart` (boys) and reuse the same pattern for girls, or one shared page that queries the correct endpoint based on the logged-in user's gender
- List view: each row shows an icon (credit = up arrow/green, debit = down arrow/red), amount (+/- coins or roses), reason label, relative timestamp ("2 hours ago") — reuse existing design-system list/card components
- Empty state for a new user with no transactions yet (reuse `AppEmptyState`)
- Linked from the wallet/recharge screen (boys) and withdraw screen (girls) — e.g. a "View all" link near the balance

---

## Part 2 — Block & Report Escalation Logic

### Rule (exact, as specified — implement precisely, do not approximate)

A user's **strike count** increases by 1 each time a report against them is filed:
- **1st strike:** account suspended for **24 hours**
- **2nd strike** (a new report filed *after* they've served the 24-hour suspension and are active again): suspended for **2 days (48 hours)**
- **3rd strike** (a new report filed after serving the 2-day suspension): **permanent ban**

A report filed *while a user is already suspended* should not add a strike or reset/extend the timer — the strike only counts against an active account being freshly reported. (Confirm this interpretation matches your intent — flag it back to me if you actually want reports-while-suspended to also count.)

> ⚠️ **Worth flagging before this ships:** an auto-escalating ban system with no human review is vulnerable to abuse — a small group could coordinate false reports to get someone banned in 3 reports with zero moderation oversight. This is your call to make (not mine), but consider whether reports need at least a lightweight admin-approval step before a strike is actually applied, versus every submitted report counting immediately as implemented below. Flagging this now since it's much easier to add before launch than after real users are wrongly banned.

### Database changes
```sql
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS strike_count INTEGER DEFAULT 0;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS suspended_until TIMESTAMPTZ;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS is_banned BOOLEAN DEFAULT FALSE;
```
(`reports` table already exists per earlier schema — no change needed there beyond what's already there.)

### Backend — `modules/moderation/`
- `moderation.service.js`:
  - `fileReport(reporterId, reportedUserId, reason)` — inserts into `reports`, then calls `applyStrikeIfEligible(reportedUserId)`
  - `applyStrikeIfEligible(userId)` — checks: is this user currently already suspended (`suspended_until > now()`) or banned? If so, per the rule above, do nothing (the report is still logged in `reports` for record-keeping, just doesn't add a strike). Otherwise, atomically increment `strike_count` and set `suspended_until`/`is_banned` based on the new count (1 → +24h, 2 → +48h, 3+ → `is_banned = true`)
  - `isUserBlocked(userId)` — returns whether a user is currently suspended or banned, and until when
- **`auth.middleware.js` update:** after verifying the Firebase token, check `isUserBlocked()` for the requesting user on every protected route. If suspended, reject with a clear error including the exact `suspended_until` timestamp (so the client can show "You can use the app again in X hours"). If banned, reject with a distinct "account banned" error — different message, no countdown.

### Flutter
- Handle the new suspension/ban error responses globally (e.g. in your API client's error interceptor) — show a dedicated full-screen state (not just a toast) explaining the suspension with a live countdown to `suspended_until`, or a permanent "account banned, contact support" screen if banned
- Report action (already partially planned from the messaging prompt) — confirm it's reachable from both chat and the active call screen, and actually calls `fileReport()`

---

## Part 3 — Chat Message Ticks (Single / Double / Seen)

Your `messages` table already has a `status` column (`sent`/`delivered`/`read`) from the messaging prompt — this part wires it to actually update correctly and reflects it in the UI, which may not be fully done yet.

### Backend
- On `send_message`: message inserted with `status = 'sent'`
- The moment the message is delivered to the recipient's active socket (i.e. they're connected and the `message:new` event was emitted to them successfully): update `status = 'delivered'`, emit a `message:status_update` event back to the **sender** with the new status
- When the recipient actually opens/views that conversation (client calls `markAsRead()`): update `status = 'read'` for all unread messages in that conversation, emit `message:status_update` to the sender for each

### Flutter
- In `chat_page.dart`, for messages sent by the current user, show a tick icon based on `status`:
  - `sent` → single grey tick
  - `delivered` → double grey tick
  - `read` → double tick in the app's primary accent color (not grey)
- Listen for `message:status_update` and update the relevant message's status in the local chat state so ticks update live without needing to reopen the screen
- Only show ticks on the current user's own sent messages, never on the other person's messages (standard chat UX)

---

## Part 4 — Online Presence: Audit, Don't Assume It's Built

Check whether real online/offline presence tracking actually exists anywhere in the codebase — it may only be a **visual placeholder** (e.g. static colored dots in early UI mockups) rather than a real backend-driven feature. Trace this rather than assuming.

### What to check
- [ ] Is there an `is_online` (or equivalent) field/state anywhere tied to a user's actual Socket.io connection status — i.e. does it update to `true` on socket connect and `false` on disconnect, server-side?
- [ ] Is presence broadcast anywhere (e.g. to a user's conversations/favorites so they see when someone comes online)?
- [ ] Or is the current "online" indicator purely cosmetic UI (a hardcoded green dot with no real data behind it)?

### If it's not real (likely, given nothing in prior prompts built this explicitly)
- Track presence server-side: on Socket.io `connection`, mark the authenticated user online (in Redis, since it's ephemeral state and Redis is already in your stack — e.g. `SET online:{userId} true` with a short TTL refreshed on activity, or a simple in-memory map if single-server for now); on `disconnect`, mark offline
- Emit a `presence:update` event to relevant other users (e.g. anyone with an open conversation with this user) when their status changes
- Flutter: reflect real presence wherever "online" is currently shown (chat screen header, conversations list, favorites) — replace any hardcoded/fake indicator with this real data

### Report back
State clearly whether presence was already real and just needed verification, or was cosmetic-only and needed to be built — don't gloss over which case it was.

---

## Final verification checklist (all four parts)

- Transaction history correctly shows only the logged-in user's own transactions, paginates properly with real history (test with more than one page's worth of data)
- Strike/suspension logic matches the exact rule in Part 2 — test the full sequence (1st report → 24h block → wait/simulate expiry → 2nd report → 2-day block → 3rd report → permanent ban) rather than just checking the first strike
- A suspended/banned user is actually blocked from all protected actions (not just login) — test hitting an API route directly while suspended
- Message ticks update correctly and live, tested with two real devices (not just one device assuming the other side saw it)
- Online presence report is honest about what was found and fixed, not just "looks good"

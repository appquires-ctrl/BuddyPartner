# Implement Gender-Differentiated Experience (Coins for Men / Roses for Women)

This is the largest structural change so far — it changes matchmaking pairing logic, the billing model, and introduces a second distinct app experience based on gender. Read fully before implementing; several pieces from earlier prompts are being **modified, not just extended**.

---

## 1. Decisions locked in for this pass

- **Pairing:** matchmaking queue must now be gender-aware. A boy is only ever paired with a girl, and vice versa — never boy↔boy or girl↔girl.
- **Earning rate:** girls earn **1 rose/minute** for a voice call, **3 roses/minute** for a video call — tracked the same way coin billing already ticks per minute.
- **Conversion:** 100 roses = ₹100 (i.e. a flat 1:1 rose-to-rupee rate). Roses start at 0 for every new girl account.
- **Withdrawal:** this pass builds the withdrawal **request** flow only (girl requests a withdrawal, it's recorded in a `pending` state). No real payout processing (no KYC, no RazorpayX) — that's a separate future decision, deliberately deferred.
- **Billing direction:** the boy in a call is debited coins exactly as already built (Section: wallet spend logic). The girl in the same call is **credited roses**, not debited anything — this is asymmetric, not the same mechanism mirrored on both sides. This changes the earlier "both participants billed independently from their own wallets" assumption from the wallet-spend prompt — that assumption was for a same-currency model and no longer applies as-is.

---

## 2. Database changes

```sql
-- Roses ledger — separate from wallets/coins, only applies to girls
CREATE TABLE IF NOT EXISTS public.rose_balances (
  user_id TEXT REFERENCES public.users(id) ON DELETE CASCADE PRIMARY KEY,
  balance INTEGER DEFAULT 0 CHECK (balance >= 0),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.rose_transactions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id TEXT REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  type TEXT CHECK (type IN ('credit', 'debit')) NOT NULL,
  amount INTEGER NOT NULL,
  reason TEXT NOT NULL,          -- 'call_minute_voice' | 'call_minute_video' | 'withdrawal_request'
  reference_id UUID,             -- callId or withdrawal request id
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Withdrawal requests — stub only, no real payout processing this pass
CREATE TABLE IF NOT EXISTS public.withdrawal_requests (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id TEXT REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  rose_amount INTEGER NOT NULL,
  rupee_amount INTEGER NOT NULL,  -- 1:1 conversion, stored explicitly rather than recomputed later if the rate ever changes
  status TEXT CHECK (status IN ('pending', 'approved', 'rejected', 'paid')) NOT NULL DEFAULT 'pending',
  requested_at TIMESTAMPTZ DEFAULT NOW(),
  processed_at TIMESTAMPTZ
);

-- No RLS (Neon, per project stack decision) — all access control enforced in Node backend query logic.
```

**On `public.users`:** confirm `gender` is already populated and reliable at signup (it is, per the auth implementation) — this field now drives which entire app experience a user gets, not just a display field, so it needs to be non-null/enforced at signup if it isn't already.

---

## 3. Backend — matchmaking changes (modifies existing logic)

- Replace the single Redis queue with **two queues**, keyed by gender (e.g. `queue:male`, `queue:female`)
- `joinQueue(userId, gender, socketId)` pushes into the queue matching that user's own gender
- The matching worker pops **one from each queue** to form a pair, instead of popping two from the same queue — still needs to be race-condition-safe under concurrent load, same requirement as before, just now cross-queue instead of single-queue
- **Balance check before queueing now differs by gender:**
  - Boys: unchanged — must have ≥ 10 coins (1 minute of voice) to join queue
  - Girls: **no balance check** — they earn, they don't spend, so there's no minimum-balance gate for them joining the queue

## 4. Backend — billing changes (modifies existing per-minute logic)

- The existing per-minute billing interval (from the wallet-spend prompt) now does **two different things per tick**, one per participant, determined by each participant's `gender`:
  - For the **boy**: unchanged — `deductForCallMinute()` at the voice/video coin rate, exactly as already built
  - For the **girl**: new — `creditRoseForCallMinute(userId, callId, callType)`: inserts into `rose_transactions` (`type = 'credit'`, `amount = 1` for voice or `3` for video, `reason = 'call_minute_voice'`/`'call_minute_video'`, `reference_id = callId`), and atomically increments `rose_balances.balance`
- **Call-ending condition changes:** the call should now only end early due to insufficient balance if the **boy's** coins run out — the girl's side has nothing that can run out, since she has no balance requirement to maintain the call. Confirm the insufficient-balance check in `calls.service.js` is updated to only check the boy's wallet, not attempt a "does the girl have enough roses" check that doesn't make sense
- Emit a `rose_update` Socket.io event to the girl on each credit, mirroring the existing `balance_update` event pattern for coins

## 5. Backend — withdrawal module (stub, this pass only)

### `modules/withdrawals/`
- `withdrawals.service.js`:
  - `requestWithdrawal(userId, roseAmount)` — validates the user actually has ≥ `roseAmount` roses, atomically debits `rose_balances` (same conditional-update pattern as coin deduction — never let balance go negative), inserts a `rose_transactions` debit row (`reason = 'withdrawal_request'`), and inserts a `withdrawal_requests` row with `status = 'pending'` and `rupee_amount = roseAmount` (1:1 rate)
  - No payout execution logic — `status` just sits at `pending` until a future pass adds real processing
- REST endpoint: `POST /withdrawals` (girl-only — reject if the requesting user's gender isn't female), `GET /withdrawals` (list her own requests + status)

---

## 6. Flutter — gender-based app routing

- After successful login/signup, read the authenticated user's `gender` from their profile and route accordingly at the **shell/router level** — not per-screen conditionals scattered everywhere:
  - Male → existing home experience (matchmaking, coin wallet, recharge) exactly as already built
  - Female → a **separate home experience** (see Section 7)
- This should be a clean fork at the routing layer (e.g. two separate `StatefulShellRoute` branches or two separate root routes chosen at login), not a single home screen with `if (gender == 'female')` branches sprinkled through shared widgets — keep the two experiences structurally separate so they can diverge further later without fighting each other

## 7. Flutter — new female experience

- **Home screen (female variant):** same matchmaking entry point/flow (queue → matched → call), but the balance chip shows **rose count**, not coins, and there is no recharge entry point in her bottom nav — replaced with a **Withdraw** entry
- **Active call screen (female variant):** same call UI, but instead of a ticking coin cost, show a live **roses earned this call** counter, updating on each `rose_update` event
- **New `features/withdraw/` feature:**
  - `withdraw_page.dart` — shows current rose balance, an input for how many roses to withdraw (with the ₹ equivalent shown live as she types, 1:1), a "Request Withdrawal" button, and a list of past requests with status badges (pending/approved/rejected/paid) — reuse existing design-system components (`AppCard`, `AppPrimaryButton`, `AppChip` for status badges)
  - `withdraw_controller.dart` (Riverpod) — calls the withdrawal REST endpoints, refreshes rose balance on success
- Bottom nav for female users: Home / Favorites / **Withdraw** / Settings (Recharge tab replaced)

---

## 8. Safety note — do not skip

Since this pass introduces real financial incentive tied to a girl staying on calls with men, this is the point where your existing block/report/rate-limit safety work (from the messaging prompt) actually matters most in practice — financial incentive can pressure someone to tolerate bad behavior they'd otherwise report. Confirm the report/block flow is genuinely reachable from the active call screen for both parties, not just from chat.

---

## 9. Explicitly deferred, not part of this pass

- Real payout processing (RazorpayX or manual bank transfer execution) — withdrawal requests just sit as `pending`
- KYC/identity verification for withdrawal eligibility
- Any minimum-withdrawal-amount enforcement, tax/TDS handling — all real financial/legal questions that need a decision (and likely legal review) before real money moves, not something to guess at in a prompt
- Admin dashboard for reviewing/approving withdrawal requests — for now these just accumulate in the `withdrawal_requests` table with no processing UI

---

## 10. Things to verify before shipping this pass

- A boy and a girl are always correctly paired — test that the two-queue matching never accidentally pairs same-gender users (e.g. due to a bug in reading the `gender` field)
- Rose crediting only happens for the girl's side of the call, coin debiting only happens for the boy's side — trace this isn't accidentally applying both to both users
- A girl's queue-join is never blocked by a balance check (since she has none) — confirm the gender-conditional logic in Section 3 is actually branching correctly, not just always applying the boy's rule
- Withdrawal request correctly prevents withdrawing more roses than the current balance (race-safe, same atomic pattern as coin deduction)
- Gender-based routing can't be bypassed or misrouted — a female account should never see the male recharge/coin UI and vice versa, test by logging in as both

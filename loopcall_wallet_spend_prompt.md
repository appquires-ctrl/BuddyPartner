# Implement Wallet Spend Logic (Calls)

Paste into your code-generation tool. Builds on completed Auth, Matchmaking, and Messaging. This wires real coin deduction into the existing call flow — no new screens, this is backend billing logic plus minor Flutter UI feedback (insufficient-balance message, live balance updates).

---

## 1. Decisions locked in for this pass

- **Voice call rate:** 10 coins/minute, ticking while connected.
- **Video call rate:** 20 coins/minute (replaces the voice rate the moment a call upgrades to video — not an add-on, a rate change).
- **Insufficient balance to start:** if a user's balance is below the cost of 1 minute of voice (i.e. < 10 coins), block them from joining the matchmaking queue at all, with a clear message (e.g. "You need at least 10 coins to start a call — recharge to continue").
- **Balance runs out mid-call:** let the in-progress minute finish (it was already paid for/granted), then end the call at the boundary of that minute if the next minute can't be covered — do not cut the user off mid-minute.
- **5-minute hard cap still applies regardless of balance** — whichever limit hits first (time or coins) ends the call.
- Both rates should be defined as named constants in one place (e.g. `CALL_RATES = { voice: 10, video: 20 }`), not hardcoded inline anywhere, so pricing can change later without hunting through the codebase.

---

## 2. Backend — Node.js/Express changes

### `modules/wallet/`
- `wallet.service.js`:
  - `getBalance(userId)` — reads current balance
  - `hasMinimumBalance(userId, requiredAmount)` — used by matchmaking's queue-join check
  - `deductForCallMinute(userId, callId, amount)` — **atomic operation**: decrements `wallets.balance` and inserts a `wallet_transactions` row (`type = 'debit'`, `reason = 'call_minute'`, `reference_id = callId`) in a single database transaction. Must never let balance go negative — use a conditional update (`UPDATE wallets SET balance = balance - $amount WHERE user_id = $userId AND balance >= $amount RETURNING balance`) and check whether a row was actually returned, rather than deducting first and checking after.

### `modules/matchmaking/` — update `joinQueue`
- Before adding a user to the Redis queue, call `wallet.service.hasMinimumBalance(userId, CALL_RATES.voice)`. If false, reject the `join_queue` socket event with a clear error payload (e.g. `{ error: 'insufficient_balance', required: 10 }`) instead of queuing them — do not let them enter the queue and fail later after potentially being matched (wastes the other user's time too).

### `modules/calls/` — add per-minute billing
- On `createCall()`, alongside the existing 5-minute hard-cap timer, start a **per-minute billing interval** (`setInterval` or repeated `setTimeout`, tied to the `callId`) that fires every 60 seconds:
  1. Look up the call's current `call_type` (voice/video) to get the correct rate
  2. Call `deductForCallMinute(userId, callId, rate)` for **both participants independently** (each side has their own wallet — confirm this is the intended model, i.e. both callers pay, not just the initiator; if only one side should pay, that changes this logic — flag this if it doesn't match your expectation)
  3. If the deduction fails for either participant (balance couldn't cover that minute), let the current minute complete (per Section 1), then trigger `endCall()` at the next tick boundary instead of immediately, and emit `call_ended` with a reason (`{ reason: 'insufficient_balance' }`) so the Flutter UI can show the right message rather than a generic "call ended"
  4. Emit a `balance_update` Socket.io event to each user after their deduction, so the Flutter UI can reflect the live balance without a separate poll
- On `upgradeToVideo()`, the *next* billing tick should use the video rate — no need to recompute anything mid-minute, the interval naturally picks up the new `call_type` on its next run
- Clear the billing interval whenever the call ends, same as the existing 5-minute timer — both must be cleaned up together to avoid orphaned timers

---

## 3. Flutter — changes

- `matchmaking_controller.dart` — handle the new `insufficient_balance` rejection from `join_queue`: show a clear message (reuse `AppErrorState` or a snackbar) instead of silently failing or getting stuck in a loading state
- `matchmaking_state.dart` — no structural change needed, existing `errorMessage` field can carry this
- Listen for `balance_update` socket events during an active call and reflect the new balance wherever it's shown (e.g. if a balance chip is visible during the call, or at minimum update the cached balance provider so the home screen is correct on return)
- Listen for `call_ended` with `reason: 'insufficient_balance'` specifically — show a distinct message ("Call ended — insufficient balance") rather than the generic end-of-call flow, so the user understands *why* it ended early
- **Note:** the wallet balance provider currently reads `100` mock/static data from initial scaffolding (per the original UI architecture prompt) — confirm this is already wired to real backend data at this point; if not, that needs to happen alongside this pass, since spend logic is meaningless against a static number

---

## 4. Things to verify before shipping this pass

- **Both participants' deductions are independent** — one user running out of balance shouldn't silently also stop billing the other user if their balance is fine (unless your intended model really is "call ends the moment *either* side can't pay," which does make sense for a 1:1 call — worth confirming this is actually the desired behavior, since it means one broke user cutting off a call the other person could afford)
- **No double-deduction on reconnect** — if a client's socket briefly drops and reconnects mid-call, the billing interval on the server shouldn't restart/duplicate; it should be tied to the `callId` server-side, independent of the client's connection state
- **Race safety** — the conditional `UPDATE ... WHERE balance >= $amount` pattern prevents a balance from going negative even under concurrent requests; don't replace it with a naive "read balance, check in application code, then write" pattern, which has a race window
- **Video upgrade mid-call at a low balance** — test upgrading to video when the remaining balance can cover voice but not video, and confirm the call ends gracefully rather than erroring

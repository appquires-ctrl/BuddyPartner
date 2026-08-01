# Major Pivot — Replace Coin/Rose Economy with Unisex Subscriptions

## 0. Branching — do this first, before any code changes

Create and switch to a new branch called **`dev`** off the current `main` before making any of the changes below. All work in this prompt happens on `dev`, not `main` — `main` stays untouched as a stable backup/rollback point in case this pivot needs to be reversed. Once `dev` is stable, it will be the branch deployed to Render; `main` is not touched by this deployment.

```bash
git checkout -b dev
```

Confirm you're on `dev` before proceeding, and do not commit any of this pivot's changes directly to `main`.

## 0.5 Riverpod — follow best practice throughout, don't default to sloppy patterns

This pivot touches a lot of state (new subscription status, new app bar indicator, deleted wallet/rose providers) — apply the same standards as a careful Riverpod codebase, not shortcuts:
- Use `NotifierProvider`/`AsyncNotifierProvider` (Riverpod 3 idioms) for the new subscription state — not a legacy `StateProvider`/`StateNotifier`, and not a plain `Provider` for something that changes over time
- `ref.watch` only inside `build()`/provider bodies — never inside callbacks (button taps, socket handlers). Use `ref.read` in callbacks, `ref.listen` for anything that should trigger navigation or a dialog (e.g. redirecting to the Subscribe screen when a gating check fails)
- The app bar subscription indicator and its live countdown timer need a proper `ref.onDispose` cleanup for the timer — don't leak a `Timer`/`Stream` that keeps ticking after the widget using it is gone
- Scope the new subscription provider correctly: it should be app-session-long (not `.autoDispose`), since the app bar indicator needs it everywhere, similar to how `walletBalanceProvider` was scoped before
- When deleting the old wallet/rose providers (per Section 5), make sure nothing left over still references them — a dangling `ref.watch(walletBalanceProvider)` on a provider that no longer exists is a build error, not a silent failure, but check for it explicitly rather than only discovering it via `flutter analyze`
- No business logic in widgets — the subscription-gating check (is this feature accessible right now) belongs in a controller/service method the widget calls, not inlined directly in a button's `onPressed`

If anything here is unclear or you want the full checklist treatment, it can be run as its own follow-up audit pass afterward, the same pattern as the earlier dedicated Riverpod audit — but apply these basics proactively while building this pivot rather than waiting to fix it after.

---

Paste into your code-generation tool. **This is the biggest structural change to the app so far** — it replaces the entire monetization model. Read fully before implementing. Old coin/rose **application code** is being deleted cleanly on this `dev` branch — `main` (per Section 0) is the preserved rollback point if the coin/rose model is ever needed again, so there's no need to comment things out in place. **Database tables are a different story — see Section 3**, since git branches don't protect against data loss the way they protect code.

---

## 1. What's changing and why

The app currently has an asymmetric economy: boys spend coins per minute, girls earn roses per minute. The client wants this removed **for now** in favor of a single, gender-neutral subscription model: **both boys and girls must have an active subscription to use the app's core features at all** (chat, voice call, video call, matchmaking). No subscription = no access to those features, regardless of gender. Once subscribed, usage is unlimited for the subscription period — no per-minute billing, no 5-minute call cap.

**What does NOT change:** gender-based matchmaking pairing (boy↔girl only, never boy↔boy or girl↔girl) stays exactly as already built. This pivot is about *access gating*, not about how people get paired.

---

## 2. Subscription plans (exact pricing)

| Duration | Price |
|---|---|
| 1 day | ₹9 |
| 4 days | ₹30 |
| 7 days | ₹50 |
| 1 month (30 days) | ₹250 |
| 1 year (365 days) | ₹2500 |

Define these as a config list/constant, not hardcoded scattered through the code — one source of truth for plan durations and prices, same principle as the earlier coin-rate constants.

---

## 3. Database changes

```sql
CREATE TABLE IF NOT EXISTS public.subscriptions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id TEXT REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  plan_duration_days INTEGER NOT NULL,
  amount_paid INTEGER NOT NULL,       -- in rupees
  started_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  payment_reference TEXT,             -- payment gateway transaction id, once payments are wired up
  created_at TIMESTAMPTZ DEFAULT NOW()
);
-- A user can have multiple historical subscription rows (renewals) — "is currently subscribed"
-- is derived by checking for any row where expires_at > now(), not a single status flag.

-- No RLS (Neon) — access control enforced in Node backend, consistent with the rest of the schema.
```

**Do not drop or alter `wallets`, `wallet_transactions`, `rose_balances`, `rose_transactions`, `withdrawal_requests`, or `is_telecaller`.** This is a firm rule regardless of the code-deletion approach below — **git branches don't protect a database.** If this pivot drops these tables/columns, that data (real user balances, transaction history) is permanently gone even if you later revert every line of application code back from `main` — there is no "undo" for a dropped table the way there is for deleted code. Leave the schema exactly as-is, simply unused by the now-deleted application code.

---

## 4. Backend changes

### New `modules/subscriptions/`
- `subscriptions.service.js`:
  - `getActiveSubscription(userId)` — returns the most recent subscription row where `expires_at > now()`, or `null` if none
  - `isSubscribed(userId)` — boolean convenience wrapper
  - `createSubscription(userId, planDurationDays, amountPaid, paymentReference)` — inserts a new row with `expires_at = now() + interval` based on the plan
  - `getTimeRemaining(userId)` — returns remaining duration (for the app bar countdown) in a format the client can easily render (e.g. total remaining hours, plus a pre-formatted label like "24 hours left" / "4 days left" / "288 days left")
- Payment: reuse whatever payment gateway integration exists/was planned for coin recharge (Razorpay) — same checkout pattern, just paying for a subscription row instead of a coin top-up. If payment integration isn't built yet, stub `createSubscription` to be called after a successful payment confirmation, same deferred pattern as before.

### Gate core features behind subscription status
Add a subscription check to **all** of the following — reject with a clear `SUBSCRIPTION_REQUIRED` error if `isSubscribed(userId)` is false:
- `join_queue` (matchmaking) — check before adding to the Redis queue, same pattern as the old balance check used to work
- Sending a chat message
- Starting/joining a call (voice or video)

### Delete cleanly — coin/rose application logic
Since `main` (Section 0) preserves the pre-pivot code as a rollback point, **delete this code cleanly on `dev` rather than commenting it out** — no dead code, no disabled-but-present functions cluttering the codebase:
- Remove the per-minute coin deduction (`deductForCallMinute`) and rose crediting (`creditRoseForCallMinute`) calls inside the call billing interval, and the functions themselves if nothing else references them
- Remove the pre-queue balance check (`hasMinimumBalance`) for boys from the matchmaking join flow
- Remove the 5-minute hard-cap timer registration in `calls.service.js` (calls are now unlimited-duration for subscribed users) — keep the general timer-cleanup *pattern* since you'll likely still want cleanup logic for whatever replaces it, just not a 5-minute-specific timer
- Remove any insufficient-balance mid-call termination logic entirely

### Telecaller screen and logic
- Delete the Telecaller opt-in onboarding step (from that prompt) so it no longer appears in the female signup flow
- Delete the Settings "Telecaller Mode" toggle
- Leave the `is_telecaller` **column** in the database (per Section 3's data-preservation rule) even though no code references it anymore

---

## 5. Flutter changes

### App bar subscription indicator (all users, both genders)
Replace the existing coin/rose balance chip in the app bar with a new subscription-status indicator:
- **Not subscribed (including expired):** a **red circle/dot** indicator — tapping it navigates to the new Subscribe screen
- **Subscribed:** a **green circle/dot** indicator plus a time-remaining label, formatted based on magnitude:
  - Under 24 hours remaining → show in hours (e.g. "18 hours left")
  - 1–29 days remaining → show in days (e.g. "4 days left")
  - 30+ days remaining → show in days still (e.g. "288 days left" for a yearly plan) — keep it simple, always show whole days once past the hours threshold, don't switch to months/years formatting
- This replaces the old coin-balance chip (boys) and rose-balance chip (girls) in the same UI slot — one unified indicator for both genders now

### New `features/subscription/`
- `subscribe_page.dart` — shows the 5 plan cards (reuse the existing recharge-plan-card visual pattern from the original recharge screen — same card shape/badge style, just with subscription durations/prices instead of coin amounts), user selects one, proceeds to the dev-only flow below (real payment integration replaces this step later)
- `subscription_controller.dart` (Riverpod) — fetches current subscription status, exposes it for the app bar indicator, handles the (currently dev-only) purchase/activation flow

### Dev-only testing tool (payment gateway isn't wired up yet)

Since real payment integration isn't built yet, tapping a plan on the Subscribe screen shouldn't dead-end waiting on a payment flow that doesn't exist. Instead, for this pass:

- Tapping a plan card navigates to a **dev-only confirmation screen** showing the selected plan's details, with two buttons:
  - **"Start Subscription (Dev)"** — calls `createSubscription()` directly, bypassing payment entirely, using the selected plan's duration (so you can actually test the green-indicator/countdown/access-gating behavior immediately, not just the plan-selection UI)
  - **"Expire Subscription Now (Dev)"** — a testing shortcut that sets the current active subscription's `expires_at` to right now, so you can immediately test the "subscription just expired" flow (red indicator returns, features re-block) without waiting out a real 1-day/4-day/etc. duration
- **Clearly label this screen/these buttons as dev-only** (e.g. a visible "DEV MODE" banner or distinct styling) so it's obvious this isn't real payment and doesn't get mistaken for a finished checkout flow
- Backend: add matching dev-only endpoints (e.g. `POST /subscriptions/dev-start`, `POST /subscriptions/dev-expire`) that do exactly this — no payment verification, just direct database writes for testing purposes
- **Before this ever goes to real users:** these dev endpoints/buttons need to be removed or gated behind an environment flag (e.g. only available when `NODE_ENV !== 'production'`) once real payment integration replaces them — flag this clearly as temporary scaffolding, not a permanent feature, so it doesn't accidentally ship as a way for real users to get a free subscription

### Gate UI entry points
- Matchmaking "Start" button: if not subscribed, tapping it should route to the Subscribe screen (or show a clear "Subscribe to start matchmaking" prompt) instead of attempting to join the queue
- Chat send button / message input: if not subscribed, show a clear inline prompt to subscribe instead of allowing typing/sending
- Same gating pattern for any direct call-initiation entry point

### Delete cleanly — Flutter side
- Remove the coin/rose live counters on the active call screen
- Recharge screen (coin purchase) and Withdraw screen (rose withdrawal) — remove their bottom-nav entry points; the screens/code themselves can be deleted too, consistent with the clean-deletion approach — `main` retains this code if it's ever needed
- Delete the Telecaller opt-in onboarding screen and Settings toggle

---

## 6. Things to verify before shipping this pass

- Gender-based matchmaking pairing still works exactly as before (boy↔girl only) — this pivot must not touch the pairing logic itself, only the access gate in front of it. Test this specifically since it's the one thing the client explicitly said not to break.
- A non-subscribed user (fresh signup, both genders) is correctly blocked from matchmaking, chat, and calls, with a clear path to the Subscribe screen — not a confusing dead end or generic error
- An expired subscription (test by manually setting `expires_at` to the past in the database) correctly reverts a user to the "not subscribed" red-circle state and re-blocks features
- The time-remaining label updates correctly across the different formatting thresholds (hours vs days) — test with a 1-day plan close to expiry and a longer plan to confirm both display correctly
- Confirm the deletion was actually clean — no leftover imports, unused providers, or dangling references to deleted files/functions causing build warnings or runtime errors
- Confirm `main` branch is untouched and still has the full pre-pivot coin/rose implementation intact, as the actual rollback point (verify this by checking out `main` separately and confirming it still builds/runs, not just assuming it's fine)
- Confirm the database tables (`wallets`, `rose_balances`, etc.) still exist and still contain the real historical data, even though no application code references them anymore

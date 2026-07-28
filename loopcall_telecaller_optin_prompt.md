# Implement: "Join as Telecaller?" Opt-In (Female Users)

Paste into your code-generation tool. Adds a new onboarding step for female users only, and a Settings toggle to change the choice later. Reference screenshot: a screen titled "Join as Telecaller?" with two selectable options — "Yes, I'm Interested" (start earning by talking to users) and "No, Just Chilling" (continue as a regular user) — with Back/Next buttons, matching the existing design system's card/radio styling.

---

## 1. What this changes

Right now, every female account automatically earns roses per call minute and has a Withdraw tab. This introduces a third real state: a female user can now opt **out** of the earning model entirely and just use the app socially (matchmaking/chat) with no roses, no earnings, no withdraw screen — this exists because not everyone installing the app wants to monetize their time, some just want to use it socially.

**This does not change anything about male users or how boys are billed.** A boy in a call still spends coins exactly as already built, **regardless of whether the girl he's matched with is a Telecaller or not** — confirm this stays true; the boy's billing logic doesn't need to know or care about the girl's telecaller status.

---

## 2. Decisions locked in for this pass

- **Where this screen appears:** as the last step of the signup sequence, in this exact order: (1) user fills in account info (name, email, password, DOB, gender, language, 18+ checkbox), taps Next → (2) avatar picker step (gender-gated set, per the avatar prompt), taps Next → (3) **only if gender is female**, this Telecaller opt-in screen appears next. Male users go straight from avatar selection to submit/finish — they never see this screen at all.
- **Default/no selection:** the user must actively choose one of the two options to proceed — don't default to either state, mirroring the reference screenshot where neither radio is pre-selected until tapped (the screenshot shows "No, Just Chilling" selected only as an example of the selected-state styling, not as a default)
- **Changeable later:** yes — add a toggle in the Settings screen so a girl can switch between Telecaller and regular modes at any time after signup, not just once at onboarding

---

## 3. Database

```sql
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS is_telecaller BOOLEAN;
-- Nullable, not defaulted to true/false — this column is only meaningful for female users,
-- and should be explicitly set at onboarding (never silently defaulted) so there's no ambiguity
-- about whether a girl has actually made this choice yet.
```

---

## 4. Backend changes

- Signup provisioning logic: accept `isTelecaller` (boolean) in the signup payload for female users only, store it in `users.is_telecaller`
- **New endpoint:** `PATCH /users/me/telecaller-status` — body `{ isTelecaller: boolean }`, female-only (reject if the requesting user's gender isn't female), updates `is_telecaller`
- **Rose-crediting logic (modifies the per-minute billing interval from the wallet-spend/gender-experience prompts):** before crediting roses to the girl's side of a call, check `is_telecaller`. If `false`, skip the rose credit entirely for that tick (no `rose_transactions` row, no balance increment) — the call itself proceeds completely normally otherwise, only the earning side is skipped
- **Withdrawal endpoints:** reject `POST /withdrawals` if the requesting user's `is_telecaller` is `false` (or null) — a non-telecaller girl shouldn't be able to request a withdrawal even if she somehow has a nonzero rose balance from before switching modes

---

## 5. Flutter changes

### New onboarding screen
- `presentation/pages/telecaller_opt_in_page.dart` — matches the reference screenshot: title "Join as Telecaller?", subtitle description, two selectable option cards (reuse existing selectable-card pattern, e.g. similar structure to a radio-style `AppCard` with a leading radio indicator), Back/Next navigation buttons
- Wire into the signup flow's step sequence for female users only — male users never see this screen at all

### Settings toggle
- Add a new section/row in the Settings screen (female accounts only) — e.g. "Telecaller Mode" with a switch reflecting current `is_telecaller` state, calling the new `PATCH /users/me/telecaller-status` endpoint on change
- Show a brief confirmation or explanation when toggling (e.g. switching off: "You'll stop earning roses from calls, but can switch back anytime") — reuse existing dialog/snackbar patterns, don't build a new confirmation component

### Gating existing UI by `is_telecaller`
- **Bottom navigation (female users):** show the **Withdraw** tab only if `is_telecaller == true`. If `false`, show whatever a "regular user" female experience should have instead in that nav slot (likely Favorites takes a more central role, or Settings — confirm the nav layout still makes sense with 3 real tabs instead of 4 for non-telecaller girls, adjust spacing/layout rather than leaving an empty gap)
- **Active call screen (female users):** the "roses earned this call" live counter should only display if `is_telecaller == true` — for non-telecaller girls, the call screen should look the same as it does for anyone else without any earnings UI at all
- **Home screen balance chip (female users):** show rose balance only if `is_telecaller == true`; otherwise, show nothing in that slot (or hide the chip entirely) rather than showing "0 roses" as if she's just not earned any yet

---

## 6. Things to verify before shipping this pass

- A female user who selects "No, Just Chilling" at signup can still use matchmaking/calls/chat completely normally — confirm the *only* thing missing for her is the earning/withdraw functionality, nothing else breaks or is unexpectedly gated
- A boy matched with a non-telecaller girl is still billed coins exactly as normal — confirm the boy's billing logic truly doesn't branch on the girl's `is_telecaller` value at all
- **Toggle takes effect in real time, mid-call included** — since the rose-crediting logic (Section 4) checks `is_telecaller` fresh on every single per-minute tick, switching the Settings toggle takes effect immediately, even during an active call: if a girl switches from Telecaller → Non-Telecaller mid-call, she stops earning roses starting from the very next tick (no roses for that minute onward). If she switches back to Telecaller mid-call, she resumes earning roses from the next tick onward. There is no "locked in for the current call" behavior — every tick independently checks her current setting at that moment.
- A non-telecaller girl genuinely cannot reach the Withdraw screen or successfully call the withdrawal endpoint even if she manually navigates there or hits the API directly (test the backend rejection, not just that the UI hides the tab)
- Existing telecaller girls (accounts created before this feature existed) — decide and confirm what happens to them: should already-active accounts default to `is_telecaller = true` (preserving current behavior) via a one-time backfill migration, since this feature didn't exist when they signed up? This needs an explicit answer, not an assumption — confirm before running any migration that touches existing user rows.

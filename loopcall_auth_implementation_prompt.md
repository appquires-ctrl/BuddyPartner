# LoopCall — Implement Authentication (Flutter + Supabase, client-driven)

Paste into your code-generation tool. This is a **real implementation pass** (not architecture-only) — builds on the existing Flutter design-system scaffold and the project context already established for this folder.

---

## 1. Ownership model (confirm before generating)

- **Flutter owns auth directly** via `supabase_flutter` — signup, login, session, logout all happen client-side against Supabase.
- **Node.js backend never issues sessions** — it only verifies the JWT Flutter sends on API calls (already planned in `auth.middleware.js`).
- **Email + password only.** No phone/OTP, no social login.
- **Session persistence — decided:** log in once, stay logged in indefinitely. `supabase_flutter` persists the session locally (auto-refresh on app restart) by default, which already gives this behavior — no inactivity timeout, no forced re-login. The only time a user should see the login screen again is if the app is uninstalled/reinstalled or local app data is cleared (session storage wiped), or if they explicitly tap "Log out."

---

## 2. What to build — Flutter side

### Setup
- Add `supabase_flutter` to `pubspec.yaml`
- Initialize Supabase in `main.dart` before `runApp` (URL + anon key from env/dart-define — **never hardcode keys**)

### Feature folder: `features/auth/`
- `presentation/pages/signup_page.dart` — fields: full name, email, password, confirm password, date of birth, gender, preferred language, **18+ confirmation checkbox** (required, not optional — do not let signup proceed without it checked)
- `presentation/pages/login_page.dart` — email + password
- `presentation/pages/forgot_password_page.dart` — triggers Supabase password-reset email
- `application/auth_controller.dart` (Riverpod) — wraps `supabase.auth.signUp()`, `signInWithPassword()`, `signOut()`, exposes an `AsyncValue`-based auth state
- `application/auth_state_provider.dart` — a `StreamProvider` on `supabase.auth.onAuthStateChange`, single source of truth for "is a user logged in" across the app

### Signup payload
When calling `supabase.auth.signUp()`, pass extra profile fields via `data:` (user metadata), e.g.:
```dart
await supabase.auth.signUp(
  email: email,
  password: password,
  data: {
    'full_name': fullName,
    'dob': dob.toIso8601String(),
    'gender': gender,
    'language': language,
  },
);
```
This metadata is what the backend trigger (Section 3) reads to populate the `public.users` row — so the client never writes directly to `public.users` or `wallets`.

### Routing (go_router)
- Add a **redirect** based on `auth_state_provider`: unauthenticated → `SplashPage`/`LoginPage`; authenticated → the existing shell route (Home/Favorites/Recharge/Settings)
- Splash page's existing CTA now routes to Login/Signup instead of being a dead-end button

### UI
- Reuse existing design-system components (`AppPrimaryButton`, `AppCard`, `AppLoadingIndicator`, `AppErrorState`) — do not create new one-off buttons/inputs for these forms
- Show inline validation errors (invalid email format, password too short, passwords don't match, age check unchecked) before hitting the network
- Show a clear, non-technical error message on Supabase failures (e.g., "email already registered") — map Supabase's raw error codes to friendly copy in one place (`auth_error_mapper.dart`), don't leak raw exceptions to the UI

---

## 3. What to build — Supabase side (SQL, run in SQL Editor)

### Auto-provision profile + wallet on signup
A Postgres trigger on `auth.users` that fires **after insert** and:
1. Inserts a row into `public.users` — `id` (= `auth.users.id`), `full_name`, `dob`, `gender`, and `language` pulled from `raw_user_meta_data`, `age_verified = true` (since checkbox was required client-side), `created_at = now()`
2. Inserts a row into `public.wallets` — `user_id`, `balance = 100` (welcome bonus on signup — matches the `100 coins` balance already used in the Flutter mock data/UI screenshots, so update this constant in one place if you change it later)

This must run in a single transaction so a user is never left with an `auth.users` row but no profile/wallet (an orphaned account).

### RLS policies (minimum required)
- `public.users`: user can `SELECT`/`UPDATE` only their own row (`id = auth.uid()`)
- `public.wallets`: user can `SELECT` only their own row; **no client-side `INSERT`/`UPDATE`/`DELETE` policy at all** — balance changes only ever happen via the Node backend's service-role client, never directly from Flutter
- Enable RLS on both tables (it's not on by default even after policies are written — must explicitly `ALTER TABLE ... ENABLE ROW LEVEL SECURITY`)

### Email confirmation
**Decision: no email confirmation required.** Disable "Confirm email" in Supabase Auth settings (Authentication → Providers → Email) so `signUp()` returns an active session immediately. This means the Flutter signup flow does **not** need a "check your email" screen/state — on successful `signUp()`, treat the user as logged in right away and route straight into the app, same as after `signInWithPassword()`.


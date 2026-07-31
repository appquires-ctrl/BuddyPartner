# Build Admin Panel — Flutter Web (New Project, Same Monorepo)

Paste into your code-generation tool. This is a **new Flutter Web app**, living alongside the existing mobile app and backend in the same project directory:

```
project_directory/
├── flutter_app/       (existing mobile app)
├── backend/            (existing Node.js/Express)
└── admin_panel/        (NEW — this prompt)
```

---

## 0. Read this before writing any UI code

**Layout reference (provided by the user):** use the general layout structure of the attached reference image — a light background, left sidebar navigation with a highlighted active state (rounded pill/rect behind the selected item), a top bar with search + profile, and a grid of rounded stat cards at the top of the dashboard with a big number, a small trend label, and a soft icon badge in the corner of each card. Match this *structural* pattern — sidebar + top bar + stat card grid — but apply LoopCall's own purple/lavender color tokens instead of the reference's blue, and adapt every label/icon/section to LoopCall's actual content, not the reference's e-commerce content (Products, Orders, Invoices, etc. don't apply here).

**Two explicit scope cuts from the reference, follow these exactly:**
- **Sidebar must only contain the sections this admin panel actually has** (Dashboard, User Management, Reports Queue, Withdrawal Requests) — do not add extra sidebar items to match the reference's fuller list (no Products, Pricing, Calendar, To-Do, Contact, Invoice, UI Elements, Team, Table, etc.). A shorter, purposeful sidebar is correct here, not a gap to fill.
- **No chart/graph on the dashboard for this pass** — skip the "Sales Details" line-chart section entirely. The dashboard is stat cards only for now (Section 3 below defines exactly which ones). Do not add a chart just because the reference has one.

**The instruction that matters most beyond the layout reference: do not default to a generic admin-template look for the *styling* even while following this structural layout.** Every AI-generated admin dashboard converges on the same thing — a dark sidebar with a blue/indigo accent, white content cards, a top bar with a search box and a bell icon, generic sans-serif everywhere. Before writing a single widget, work through a short design plan first (in your own reasoning, not shown to me until decided):

1. **Color:** pick 4–6 named hex values that actually derive from LoopCall's existing brand (the purple/lavender palette from the mobile app's `AppColors` tokens) — reuse those tokens directly rather than inventing a separate "admin blue," so this genuinely looks like the same product's control room, not an unrelated SaaS template bolted on
2. **Typography:** a clear type scale with real hierarchy (a display weight for section headers, a body face for table content, a monospace or tabular-numeral treatment specifically for numeric data like coin balances, rose counts, and rupee amounts — numbers in a data table should visually align and feel precise, not just reuse body text styling)
3. **Signature element:** one thing this admin panel does visually that a generic template wouldn't — could be how banned/flagged users are visually distinguished in a table, how the rose-to-rupee conversion is displayed, or how the report queue is presented. Pick one and commit to it.

This is an **internal tool, not a marketing page** — so the bar isn't "impressive," it's "fast to scan, hard to misread, and clearly part of the same product as the app." Data density and clarity win over decoration. But "functional" doesn't mean "the default Material admin template" — apply real intentionality to color/type/spacing even in a dense data tool.

---

## 1. Tech stack

- Flutter Web (same Flutter/Dart version as the mobile app)
- Riverpod 3 for state management (consistent with the mobile app)
- go_router for navigation
- Reuse the mobile app's design tokens (`AppColors`, `AppSpacing`, `AppRadius`, typography) as a starting point/shared reference — either by referencing the same values directly or copying the token files into `admin_panel/` and adapting for web layout density (tighter spacing than mobile touch targets, since this is mouse/keyboard-driven)
- Data tables: use a real data table widget (Flutter's `DataTable`/`PaginatedDataTable` or a custom-built one) — not a `ListView` of ad-hoc rows pretending to be a table

---

## 2. Auth (basic, for this pass)

- **No Firebase Auth, no user accounts, no `is_admin` flag on `users`.** This is a single shared admin password, not a multi-account login system.
- A simple table to hold it:
  ```sql
  CREATE TABLE IF NOT EXISTS public.admin_config (
    id INTEGER PRIMARY KEY DEFAULT 1,
    password_hash TEXT NOT NULL,
    CONSTRAINT single_row CHECK (id = 1)
  );
  ```
  (`single_row` constraint keeps this table to exactly one row — there's only ever one admin password.)
- The developer sets the password directly via Neon (a one-time manual `INSERT`/`UPDATE` with a bcrypt-hashed value) — no in-app "create admin account" flow, no signup screen.
- **The admin panel itself is just one screen: a password field.** Login flow: the field only sends a request to the backend if the entered text starts with `_` — if it doesn't, show "Wrong password" instantly with zero network call (this filters out accidental/junk taps without hitting the API at all). If it does start with `_`, strip that leading `_` character client-side, send the remaining string to the backend verify endpoint, which compares it against `password_hash` as normal (bcrypt compare). Correct match → issue a session (a simple signed token/cookie) → land on the dashboard. Wrong password (with or without the `_` prefix) → clear error, no lockout/rate-limit complexity needed for this pass (this is a single trusted developer/team using it, not a public-facing login).
- No roles/permissions tiers — there's only one admin level, and only one shared password, by design.

---

## 3. Core features for this pass

### Dashboard (landing page after login)
- **Stat cards only — no chart/graph for this pass** (per Section 0's scope cut). A grid of rounded stat cards, each with a big number, a small trend/context label, and a soft icon badge — styled after the reference layout's card pattern but in LoopCall's own colors
- Cards to include: total users (split male/female), active/pending withdrawal requests, total reports filed today/this week, total coins recharged (revenue proxy), total roses paid out — real numbers from the backend, not placeholders
- Keep this genuinely useful at a glance, not a wall of every metric you could compute — pick the ones that matter for a first look at app health

### User Management
- Searchable, paginated table of all users: name, gender, email, signup date, `is_banned` status, `strike_count`/report count
- Actions per row: view detail (their profile info, call history summary, report history), **ban** / **unban** toggle (calls the same backend logic as the manual SQL process, but as a real button instead of raw SQL — this is the actual value-add of having a panel at all)
- Filter by gender, banned status

### Reports Queue
- List of filed reports (from `public.reports`), showing reporter, reported user, reason, timestamp
- Since the ban logic is now automatic (3 distinct reporters), this view is mainly for **visibility/audit** — let the admin see what's been reported and why, even though banning already happens automatically at the threshold
- Ability to manually ban a user directly from this view too (for cases below the 3-reporter threshold that still look bad on review)

### Withdrawal Requests
- Table of `withdrawal_requests`: user, rose amount, rupee amount, status, requested date
- Since real payout processing isn't built yet, the admin action here is just updating `status` (pending → approved/rejected/paid) as a manual record-keeping step — no real payment execution yet, consistent with what's already deferred in the wallet-spend/withdrawal prompts

### Transactions Overview (optional if time allows, lower priority than the above three)
- Read-only view of recent `wallet_transactions`/`rose_transactions` across all users, for spotting anomalies

---

## 4. Things to verify

- The admin panel visually reads as the same brand as the mobile app (shared color tokens), not a disconnected generic dashboard
- Only the correct admin password grants access — test that a wrong password is rejected and no session is issued, and that the dashboard/API routes aren't reachable without a valid session
- **Client-side prefix gate:** the password field only triggers the backend verify call if the entered text starts with `_`. If it doesn't start with `_`, show "Wrong password" immediately, client-side, with no network request at all. When it does start with `_`, strip that leading `_` before sending the rest to the backend, which compares the stripped value against `password_hash` as normal.
- Ban/unban actions from the UI actually call real backend endpoints and reflect in the main app immediately (a banned user should be locked out on their next request, same as the manual SQL process achieves)
- Tables handle empty states (no users match filter, no pending withdrawals) with real designed empty states, not a blank white area
- Responsive down to a reasonably small laptop width — this doesn't need mobile support, but shouldn't break on a 1280px-wide screen

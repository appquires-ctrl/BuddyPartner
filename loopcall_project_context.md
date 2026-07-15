# LoopCall — Project Context (Read & Remember Only — Do Not Generate Files)

**Instruction to the AI tool:** Read this entire brief and hold it as project context/memory **for this folder only** — do not apply or carry these decisions to any other project or directory. This is background only — **do not create, edit, or scaffold any files in this turn.** Just confirm you understand the product, the current state of the codebase, and the roadmap, so future prompts in this directory can build on it without re-explaining. Reply with a short summary of your understanding, not code.

---

## 1. What we're building

**LoopCall** — a coin-based "talk to a stranger" calling app, similar in concept to the Play Store app `com.dating.for.all`. Users buy coins, spend coins to connect with telecallers/matches over voice calls, and can favorite people they've connected with before.

## 2. Current state of this directory

- **Frontend:** Flutter app — UI/design-system layer only has been scaffolded so far (Clean Architecture, Feature-First, Riverpod 3 provider *shells* with mock data, go_router, Material 3). No business logic, no API integration, no real state management yet.
- **Backend:** Node.js + Express + JavaScript, Supabase for auth and Postgres — architecture and schema planned (modular/layered: routes → controllers → services), not yet implemented at the time of this note.

## 3. Build sequencing

We are recreating the functionality of `com.dating.for.all` (Play Store), but **not all at once**. Build order:
1. **Phase 1 (current focus):** Authentication → Matchmaking → Messaging (chat) — the three core features below, in this order.
2. **Phase 2 (later):** Wallet/coins, recharge, favorites, telecaller-specific flows, settings, and the rest of the reference app's feature set.

Do not jump ahead to Phase 2 features unless explicitly asked — get auth, matchmaking, and messaging solid first.

## 4. Full product scope (for future reference — not all built yet)

**Core user flow:**
1. Splash → signup/login — **email + password via Supabase Auth only. No phone/OTP login.**
2. Home screen — a "Matchmaking" entry point (see below) plus, later, browsing available telecallers, coin balance, empty states
3. Matchmaking call — connects two random users, then later spends coins per telecaller-connect (per-minute or per-call — TBD)
4. Chat/messaging — 1:1 text chat, likely tied to matched/connected users (see below)
5. Favorites — save people/telecallers to revisit (Phase 2)
6. Recharge — buy coin packs via a payment gateway (Razorpay likely, given ₹ pricing), plan cards with special-offer/discount badges (Phase 2)
7. Settings — profile, account management (Phase 2)

### Core Feature: Matchmaking (Phase 1 priority)

- User taps a "Matchmaking" action on the home screen.
- Backend places them into a **matchmaking queue**; any other user who has also tapped matchmaking at roughly the same time gets paired with them — fully random pairing, not friend-selection. Must scale to thousands of concurrent users queuing simultaneously in production, so pairing needs to be fast and race-condition-safe (queue managed in **Redis**, not a naive DB polling loop).
- Once paired, both users are connected via a **voice call**, capped at a **5-minute** limit by default.
- Users have the option to **switch from voice to video** mid-call (upgrade path, not mandatory).
- Real-time signaling/events (queue status, match-found notification, call-state changes, upgrade-to-video signal) go over **Socket.io**.
- Actual voice/video transport goes over **Agora** (Agora Voice + Video SDK) — backend is responsible for generating/issuing Agora tokens per call session, not for media transport itself.

**Planned entities/tables:** users, matchmaking_queue (or Redis-only, TBD), calls (call type: voice/video, duration, participants), conversations, messages, message_reads, wallets, wallet_transactions, telecallers, favorites, reports (safety/moderation) — wallet/telecaller-specific tables are Phase 2.

**Known open decisions** (to be resolved in future sessions, not now):
- Whether the 5-minute cap is hard-cut or extendable with coins
- Whether video upgrade costs coins or is free during Phase 1
- Age verification / 18+ gating approach
- Wallet spend model once telecaller flow (Phase 2) is built (per-minute vs per-call)
- Payment gateway integration
- Whether telecallers (Phase 2) are a role on the same `users` table or a separate actor/auth flow
- Whether matchmaking queue state lives purely in Redis or is also mirrored to Postgres for history/analytics
- Whether messaging is open between any two users, or restricted to users who've completed a matchmaking call together (affects abuse surface)

### Core Feature: Messaging / Chat (Phase 1, built after matchmaking)

- Standard 1:1 text chat between matched/connected users, with room to extend to media messages later.
- **Data model:**
  - `conversations` — id, participant ids, created_at, last_message_at
  - `messages` — id, conversation_id, sender_id, content, type (text/image/system), status (sent/delivered/read), created_at
  - `message_reads` — conversation_id, user_id, last_read_message_id (drives unread counts without scanning all messages)
- **Transport:** reuse **Socket.io** (already in the stack for matchmaking/calls) for real-time delivery, typing indicators, and read receipts — no second real-time system.
- **Persistence:** every message is written to **Postgres (Supabase)** first as source of truth, then broadcast over the socket. Never broadcast-then-persist, or messages can be lost if the socket drops mid-send.
- **Offline delivery:** no separate queue needed — offline recipients just pull backlog from Postgres on reconnect/history fetch.
- **Media messages:** attachments (images/voice notes) go to **Supabase Storage**, message row stores a URL + type, not the binary.
- **REST endpoints (history, not live delivery):** `GET /conversations` (list + unread counts), `GET /conversations/:id/messages` (cursor-paginated), `POST /conversations/:id/messages` (fallback/write path).
- **Safety:** blocked users' messages must be rejected **server-side**, not just hidden client-side; report-message ties into the existing `reports` table; rate-limit message sends to prevent spam/harassment.
- **Explicitly NOT used for this feature:** Redis (scoped to matchmaking queue only, not chat storage), Firebase/Firestore, Supabase Realtime, or any other real-time provider — Socket.io + Postgres + Supabase Storage is the full stack for messaging. Firebase Cloud Messaging (FCM) may re-enter later, but only for background push notifications, not for chat delivery itself — that's a separate, later concern.

## 5. Tech stack (both sides)

**Frontend:** Flutter (latest stable), Dart, Clean Architecture + Feature-First, Riverpod 3, go_router, responsive_framework, Material 3, flutter_animate

**Backend:** Node.js + Express.js (JavaScript, no TypeScript), Supabase Auth (**email/password only, no phone OTP**) + `@supabase/supabase-js` client only (no Prisma/Knex), Zod/Joi validation, helmet/cors/rate-limiting, deployed to Railway/Render

**Real-time/calling stack (new — needed for matchmaking):**
- **Redis** — matchmaking queue + pairing logic, must handle high concurrent throughput safely
- **Socket.io** — real-time events (queue status, match found, call state, video-upgrade signal)
- **Agora** — voice + video call transport; backend issues Agora session tokens, does not handle media itself

## 6. Design language (for consistency in any future UI work)

Purple/lavender brand palette, soft gradient splash background, dark "wallet card" for balance display, badge-ribbon pricing cards (SPECIAL OFFER / X% OFF), rounded/geometric sans typography, 4-tab bottom nav (Home / Favorites / Recharge / Settings).

## 7. What I want from you right now

Just acknowledge and retain this context. When I come back in a future session and ask you to build a specific feature (e.g., "implement the wallet module" or "wire up the recharge screen to the backend"), use this brief to stay consistent with the architecture, naming, and product decisions already established — without me needing to re-paste all of this.

**Do not generate, scaffold, or modify any files in response to this message.**

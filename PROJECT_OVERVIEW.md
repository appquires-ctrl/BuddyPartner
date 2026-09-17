# Project Overview: BuddyPartner (Dating & Real-Time Companion Platform)

## 1. Executive Summary
**BuddyPartner** is a real-time companionship, matchmaking, and 1:1 live audio/video calling mobile application designed for the Indian and international markets. The platform operates on a **dual-balance coin economy** (`spendable_balance` vs. `earned_balance`) alongside a **unisex membership subscription model**. 

Calling access is governed by active subscriptions (unlimited calling while subscribed), while coins are spent on Buddy activity requests, gifts, and platform interactions. Verified users redeem platform-awarded `earned_balance` for real-currency bank/UPI withdrawals. **There is NO per-minute coin billing or per-minute call earning on calls.**

The ecosystem consists of three major components:
1. **Mobile Application**: A Flutter client (Android/iOS) featuring real-time Agora calling, Socket.IO messaging, Google Play In-App Purchases, location-based discovery, and a "Buddy" activity broadcast system.
2. **Admin Web Panel**: A Flutter Web dashboard for user management, host KYC/onboarding, withdrawal approvals, banner/ad management, report moderation, and app version enforcement.
3. **Backend API & Real-Time Engine**: A Node.js/Express service backed by PostgreSQL, Redis (pub/sub, caching, rate limiting, and presence), Socket.IO (stateful clustering via `@socket.io/redis-adapter`), Firebase Admin SDK (multicast FCM push notifications), and Agora RTC token generation.

---

## 2. Technical Stack & Infrastructure

### Mobile Client (`/lib`)
- **Framework**: Flutter (Dart SDK `^3.11.0`, targeting Android & iOS)
- **State Management**: Riverpod (`flutter_riverpod: ^2.5.1`)
- **Navigation / Routing**: `go_router: ^14.2.0` with strict route-level guards
- **Networking**: `dio: ^5.7.0` with token refresh interceptors and unified error logging
- **Real-Time Communication**:
  - WebSockets: `socket_io_client: ^3.0.2`
  - Audio & Video Calling: `agora_rtc_engine: ^6.5.0`
- **Push Notifications**: Firebase Messaging (`firebase_messaging: ^15.1.3`, `firebase_core: ^3.6.0`)
- **In-App Purchases**: `in_app_purchase: ^3.2.0` (Google Play Billing API)
- **Security & Privacy**: `screen_protector: ^1.5.3` (prevents screen capture/recording on private profiles/calls), `flutter_secure_storage: ^9.2.2` (biometric/hardware keystore encryption for JWTs)
- **Geolocation**: `geolocator: ^13.0.1` and `geocoding: ^3.0.0` (reverse geocoding GPS coordinates to city/state)
- **Analytics & MMP**: `apptrove_sdk_flutter: ^2.0.7`

### Admin Panel (`/admin_panel`)
- **Framework**: Flutter Web (`admin_panel/lib`)
- **Hosting**: Netlify / Cloudflare Pages (`netlify.toml` configured)
- **Core Modules**:
  - User and Host Management (banning, status inspection, verification)
  - Withdrawal Request Approvals (UPI/NEFT bank payouts)
  - Content & User Reporting Moderation
  - Banner Advertisements & Carousel Campaigns
  - Dynamic App Version Control & Force Update Flags

### Backend Service (`/backend`)
- **Runtime**: Node.js (`>=18.0.0`), Express (`^4.21.0`)
- **Primary Database**: PostgreSQL (`pg: ^8.22.0`) with connection pooling, transactional row-level locks, and indexed queries
- **Cache, Presence & Pub/Sub**: Redis (`ioredis: ^5.4.1`) paired with `@socket.io/redis-adapter: ^8.3.0`
- **Real-Time Engine**: Socket.IO (`^4.7.5`) handling call signaling, presence rooms, and broadcast events
- **Media & File Storage**: Cloudinary (`cloudinary`, `multer-storage-cloudinary`)
- **Calling Infrastructure**: Agora Access Token Generator (`agora-access-token: ^2.0.4`)
- **Payment Verification**: Google Play Developer API (`googleapis: ^176.0.0`) and Razorpay (`razorpay: ^2.9.8`)
- **Push Engine**: Firebase Admin SDK (`firebase-admin: ^12.7.0`) with custom chunked multicast batching (<= 500 tokens per dispatch)
- **Security & Hardening**: `helmet`, `bcryptjs`, `jsonwebtoken`, `express-rate-limit` with `rate-limit-redis`

---

## 3. Repository Directory Structure

```text
dating_app/
├── admin_panel/                     # Flutter Web Admin Dashboard
│   └── lib/
│       ├── features/                # Ads, Auth, Dashboard, Reports, Users, Withdrawals
│       └── services/                # Admin REST API clients
├── backend/                         # Node.js/Express Real-time Backend
│   ├── config/                      # Database, Redis, and Environment configs
│   ├── migrations/                  # SQL migration scripts (000 to 020)
│   ├── modules/
│   │   ├── admin/                   # Admin auth, user controls, withdrawal review
│   │   ├── advertisements/          # In-app promotional banners
│   │   ├── auth/                    # OTP verification, JWT generation & rotation
│   │   ├── buddy/                   # Buddy Activity broadcast, accept -> chat, OTP -> reward
│   │   ├── calls/                   # Agora RTC token generation, call signaling, lifecycle
│   │   ├── instant_connect/         # Fast 1:1 matching algorithm
│   │   ├── matchmaking/             # City & gender filtered profile browsing
│   │   ├── messaging/               # 1:1 direct chat, message history, read receipts
│   │   ├── moderation/              # Reports, auto-ban triggers, blocking
│   │   ├── payments/                # Google Play IAP & Razorpay verification
│   │   ├── presence/                # Online/offline/in-call heartbeat tracking
│   │   ├── subscriptions/           # Unisex VIP passes (1 mo, 6 mo, 1 yr)
│   │   ├── wallet/                  # Dual-balance wallets, ledger, spendable-first debits
│   │   └── withdrawals/             # Earned-balance payout requests & settlement
│   ├── services/
│   │   ├── cache.service.js         # Unified Redis cache and pattern invalidator
│   │   └── firebase.service.js      # Multicast batching (<= 500 tokens) & push delivery
│   ├── redis.js                     # Redis connection client & memory fallback
│   ├── db.js                        # PostgreSQL connection pool (max: 40) & query profiler
│   ├── test_*.js                    # Comprehensive automated test suites
│   └── server.js                    # Entry point & socket routing
└── lib/                             # Flutter Mobile Client
    ├── app/                         # App entry, themes, and GoRouter route definitions
    ├── core/
    │   ├── errors/                  # Custom exceptions & failures
    │   ├── network/                 # Dio client, logging, interceptors
    │   ├── services/                # Screen protector, location, notification services
    │   └── theme/                   # High-contrast glassmorphic design system
    └── features/
        ├── auth/                    # Login, OTP input, user session provider
        ├── buddy/                   # Buddy activities carousel, create sheet, OTP modal
        ├── call/                    # Agora Audio/Video call views, call overlay
        ├── chat/                    # 1:1 chat UI, media sharing, conversation list
        ├── home/                    # Discover, banners, "Let's Connect", location badge
        ├── profile/                 # User profile editor, photos, verification badge
        ├── recharge/                # Coin store, Google Play IAP sheet
        ├── subscription/            # Unisex VIP subscription plans & unlimited call access
        ├── wallet/                  # Dual-balance display, transaction history
        └── withdraw/                # Earned-balance withdrawal portal
```

---

## 4. Key Feature Architectures & Business Logic

### A. The "Buddy" Activity Broadcast & Meetup System
Designed for spontaneous real-life and virtual companionship activities (e.g. Movie Buddy, Pizza Buddy, Coffee Buddy, Gym Buddy):
1. **Creation**:
   - Initiator chooses an activity, target city, and target gender.
   - **Cost**: 100 coins debited atomically (spendable balance first, then earned balance).
   - If total balance across both buckets < 100, rejected with HTTP 400 (`INSUFFICIENT_COINS`) with zero database writes.
2. **Broadcast**:
   - Backend broadcasts in real-time via Socket.IO room `buddy:city:{city}:{gender}`.
   - Offline matching users receive an FCM multicast push in chunks of <= 500 tokens (supporting 5,000+ users).
3. **Atomic Acceptance & Immediate Chat Unlock**:
   - Multiple candidate users may see the request, but acceptance uses PostgreSQL atomic update:
     `UPDATE buddy_requests SET status = 'accepted', accepter_id = $2 WHERE id = $1 AND status = 'open'`.
   - First user to accept wins; all others receive **HTTP 409 Conflict** (`ALREADY_ACCEPTED`).
   - **Chat unlocks immediately on acceptance**: A 1:1 conversation is created right away so the two users can message and arrange their meetup.
4. **In-Person Meetup & OTP Verification**:
   - Upon acceptance, backend generates a 6-digit numeric OTP via CSPRNG and stores only its secure hash.
   - The initiator fetches the OTP via authenticated REST endpoint (`GET /api/buddy/requests/:id/otp`).
   - They meet in real life, and the initiator verbally shares the OTP with the accepter.
   - Accepter submits the OTP. Submissions are rate-limited in Redis (max 5 attempts, then 15-minute lockout).
   - Once verified: Status transitions to `completed`, and the accepter receives **50 coins credited strictly to `earned_balance`**.

### B. Real-Time 1:1 Calling (Agora + Unisex Subscriptions)
- **Calling Access**: Governed exclusively by **unisex membership subscriptions** (1 Month, 6 Months, 1 Year). Users with an active subscription have unlimited 1:1 audio and video calling access.
- **NO Per-Minute Coin Deductions**: Male callers are NOT charged coins per minute.
- **NO Per-Minute Call Earnings**: Female call recipients do NOT earn coins or roses per minute.
- **Signaling Flow**: Initiated via Socket.IO (`call_user` -> `call_incoming` -> `accept_call` / `reject_call` -> `call_connected`).
- **RTC Engine**: Dynamic Agora RTC channel tokens generated by the backend (`agora-access-token`).

### C. Dual-Balance Coin Economy & In-App Purchases
The ledger enforces a strict dual-balance architecture to maintain compliance and eliminate cash-out loopholes:
- **`spendable_balance`**: Funded by Google Play In-App Purchases, promos, and admin grants. Can be spent on Buddy requests, gifts, and in-app interactions. **Never withdrawable as cash.**
- **`earned_balance`**: Funded exclusively by platform rewards (e.g. +50 coins on Buddy meetup completion, scratch card rewards). **Withdrawable to real-currency bank accounts / UPI.**
- **Debit Ordering**: Any coin spend debits `spendable_balance` first, then `earned_balance`.
- **Idempotency**: All coin movements require client-generated idempotency keys to prevent duplicate charges or credits.

### D. Host Earning & Bank Withdrawals
- Users with earned coins can request payouts via the **Withdrawal Portal** (`WithdrawPage`).
- Withdrawals source exclusively from `earned_balance`; `spendable_balance` is rejected server-side.
- At request time, coins are atomically deducted from `earned_balance` and held in status `pending`.
- A database partial unique index restricts users to at most 1 concurrent pending withdrawal.
- If admin approves: Status changes to `paid` (no balance change).
- If admin rejects: Coins are credited back to `earned_balance` with a compensating ledger transaction.

### E. VIP Membership & Subscriptions
- Multi-tier passes: 1 Month, 6 Months, 1 Year.
- Subscription perks include:
  - Unlimited 1:1 audio and video calling
  - Daily instant matches ("Let's Connect")
  - Profile badge & increased discoverability
  - Exclusive access to broadcast Buddy requests

### F. Security, Privacy & Moderation
- **Screen Protection**: `ScreenProtectionService` activates Android `FLAG_SECURE` to prevent screenshots and screen recording on private chat, calling, and photo screens.
- **Reporting & Auto-Ban**: Users can report profiles for inappropriate behavior. After a threshold of distinct reporters, the user is temporarily auto-banned pending admin review.
- **Single Active Session**: Tokens and socket connections enforce single-device logins via Redis session tokens, preventing credential sharing.

---

## 5. Primary Database Entities (PostgreSQL)

| Table | Purpose & Key Columns |
|---|---|
| `users` | Core profile: `id`, `phone_number`, `full_name`, `gender`, `city`, `is_banned`, `avatar_seed`, `avatar_style`, `created_at` |
| `wallets` | Dual-balance store: `user_id`, `spendable_balance BIGINT`, `earned_balance BIGINT`, `CHECK(>= 0)` |
| `wallet_transactions` | Audit ledger: `id`, `user_id`, `spendable_delta`, `earned_delta`, `idempotency_key UNIQUE`, `reason`, `reference_id`, `created_at` |
| `buddy_requests` | Activity requests: `id`, `initiator_id`, `accepter_id`, `buddy_type`, `city`, `target_gender`, `status` (`open`/`accepted`/`completed`/`cancelled`), `otp_hash`, `conversation_id`, `created_at`, `completed_at` |
| `conversations` | 1:1 chat threads: `id`, `user_a_id`, `user_b_id`, `created_at`, `last_message_at` |
| `messages` | Direct messages: `id`, `conversation_id`, `sender_id`, `content`, `media_url`, `is_read`, `created_at` |
| `calls` | Call history & session tracking: `id`, `caller_id`, `matched_user_id`, `status`, `call_type` (`voice`/`video`), `duration_seconds`, `started_at`, `ended_at` |
| `subscriptions` | Active passes: `id`, `user_id`, `plan_duration_days`, `amount_paid`, `started_at`, `expires_at` |
| `withdrawals` | Payout requests: `id`, `user_id`, `amount`, `status` (`pending`/`approved`/`rejected`/`paid`), `idempotency_key`, `created_at`, `processed_at` |

---

## 6. Git Branching & Contribution Rules

Strictly enforced across all agentic and developer workflows:
- **`main` branch**: Untouched primary production backup. **Never push or commit to `main` directly.**
- **`dev` branch**: Primary active development branch. All features, bug fixes, and tests are committed and pushed here.
- **Remotes**:
  - `buddypartner`: `https://github.com/appquires-ctrl/BuddyPartner.git`
  - `origin`: `https://github.com/Dhruv9696490/Dating-App.git`
- **Confirmation Policy**: Never execute `git commit` or `git push` without explicit user confirmation.

---

## 7. Current Project Health & Recent Milestones
1. **Unisex Subscription Architecture**: Calling is completely decoupled from coin metering. Active subscribers enjoy unlimited 1:1 calls.
2. **Dual-Balance Ledger & Buddy Meetup Overhaul**: Fully implemented in Migration 016 (`wallets`, `wallet_transactions`, and `buddy_requests`). Separates non-withdrawable `spendable_balance` from platform-rewarded `earned_balance`. Chat unlocks immediately upon request acceptance; the in-person 6-digit CSPRNG OTP is strictly proof of the real-world meetup and triggers the 50-coin reward to `earned_balance`.
3. **Zero-Balance & Insufficient Funds Guard**: Verified with automated test suite (`test_buddy_insufficient_balance.js`). Accounts with < 100 coins are cleanly rejected with 0 orphaned rows and 0 ledger deductions.
4. **FCM Multicast Batching (<= 500)**: Verified with test suite (`test_fcm_batching.js`). Chunks up to 5,000 device tokens into <= 500 token slices to ensure zero silent dropouts or Firebase API limit violations.
5. **Flutter 3.27+ Compatibility**: UI components hardened against modern Flutter framework constraints (e.g. `Material` wrapping for `ListTile` in custom modal sheets).
6. **Scalability & Latency Hardening**:
   - Migration 019: Functional index on `LOWER(TRIM(city))` on `public.users` for instant city discovery.
   - Migration 020: Partial index on `public.messages(conversation_id, status) WHERE status = 'sent'` and direct foreign key indexes on `conversations(user_a_id)` and `conversations(user_b_id)` to optimize real-time delivery reconciliation on socket connect.
   - Subscriptions Cache: `isSubscribed(userId)` wrapped in Redis with 300s TTL and write invalidation, cutting 200–500 QPS from chat.
   - In-Memory App Config: Version checks served from local memory with 60s background refresh, eliminating Redis reads on every HTTP request.
   - Connection Pool: Sized to `max: 40` on Neon's PgBouncer pooler endpoint.

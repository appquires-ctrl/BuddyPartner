# Stage 3 Follow-Up Answers & Stage 4 Design Review

**Author:** DeepMind Agentic Pair Programmer  
**Date:** September 20, 2026  
**Status:** Design Proposal & Verification Document (No code changes implemented in this pass)  

---

## Section 1 — Ban Status Durability

### 1.1 Does `user_active_session:${userId}` have a TTL?
**No, it does not have a TTL.**

In [`backend/modules/auth/auth.routes.js`](file:///c:/Users/dhruv/AndroidStudioProjects/dating_app/backend/modules/auth/auth.routes.js), session keys are written at three distinct sites:
1. **Password Login (line 238):**
   ```javascript
   await redis.set(`user_active_session:${user.id}`, JSON.stringify({ sessionId, isBanned: Boolean(user.is_banned) }));
   ```
2. **OTP Verification / Signup (line 860):**
   ```javascript
   await redis.set(`user_active_session:${user.id}`, JSON.stringify({ sessionId, isBanned: Boolean(user.is_banned) }));
   ```
3. **Token Refresh (line 989):**
   ```javascript
   await redis.set(`user_active_session:${id}`, JSON.stringify({ sessionId: currentSessionId, isBanned: Boolean(user.is_banned) }));
   ```

None of these `redis.set` calls pass an `'EX'` (expiration) parameter. The key is persisted indefinitely in Redis until explicitly overwritten by a new login or deleted via logout (`redis.del`).

---

### 1.2 Does the login flow independently check `users.is_banned` in PostgreSQL?
The behavior diverges depending on the authentication path:

#### Path A: Password Login (`POST /api/auth/login`)
- **Yes**, PostgreSQL is checked.
- **Code Reference:** [`backend/modules/auth/auth.routes.js` lines 145–189](file:///c:/Users/dhruv/AndroidStudioProjects/dating_app/backend/modules/auth/auth.routes.js#L145-L189):
  ```javascript
  const userRes = await db.query(
    `SELECT u.id, ..., u.is_banned, ... FROM public.users u WHERE ...`
  );
  const user = userRes.rows[0];
  if (user.is_banned === true) {
    return res.status(403).json({ error: 'ACCOUNT_BANNED', message: 'This account has been suspended or banned.' });
  }
  ```
  If a banned user attempts to log in using a password, PostgreSQL is queried directly, and the login is rejected with HTTP 403.

#### Path B: OTP Verification / Mobile Login (`POST /api/auth/otp/verify`)
- **No**, PostgreSQL is **NOT** checked for ban status.
- **Code Reference:** [`backend/modules/auth/auth.routes.js` lines 743–752](file:///c:/Users/dhruv/AndroidStudioProjects/dating_app/backend/modules/auth/auth.routes.js#L743-L752):
  ```javascript
  let userResult = await db.query(
    `SELECT u.id, u.country_code, u.mobile, u.phone_number, u.full_name, u.user_name, u.password_hash, u.dob, u.gender, u.language, 
            u.avatar_seed, u.avatar_style, u.is_telecaller, u.has_claimed_intro_offer, 
            u.country, u.state, u.city, u.latitude, u.longitude, u.incoming_paid_calls_enabled,
            w.spendable_balance, w.earned_balance, (COALESCE(w.spendable_balance, 0) + COALESCE(w.earned_balance, 0)) AS balance 
     FROM public.users u
     LEFT JOIN public.wallets w ON w.user_id = u.id
     WHERE (u.country_code = $1 AND u.mobile = $2) OR u.phone_number = $3`,
    [cleanCountryCode, cleanMobile, fullPhoneNumber]
  );
  ```
  Notice that `u.is_banned` is **completely omitted from the SELECT clause**.
- Between lines 753 and 865, `user.is_banned` is never validated.
- At line 860:
  ```javascript
  await redis.set(`user_active_session:${user.id}`, JSON.stringify({ sessionId, isBanned: Boolean(user.is_banned) }));
  ```
  Since `user.is_banned` was never selected, `user.is_banned` is `undefined`. In JavaScript, `Boolean(undefined) === false`.

#### Path C: Token Refresh (`POST /api/auth/token/refresh`)
- **No**, PostgreSQL is **NOT** checked for ban status.
- **Code Reference:** [`backend/modules/auth/auth.routes.js` lines 976–980](file:///c:/Users/dhruv/AndroidStudioProjects/dating_app/backend/modules/auth/auth.routes.js#L976-L980):
  ```javascript
  const userRes = await db.query(
    `SELECT id, country_code, mobile, phone_number, full_name, city, gender, incoming_paid_calls_enabled FROM public.users WHERE id = $1`,
    [id]
  );
  ```
  `is_banned` is omitted here as well. If `activeSessionId` is missing from Redis, line 989 sets `isBanned: Boolean(user.is_banned)` which evaluates to `false`.

---

### 1.3 Bug Confirmation
**Confirmed: This bug exists today in the primary mobile authentication path (`POST /api/auth/otp/verify`).**

If a banned user's Redis key is lost (via Redis restart, memory LRU eviction, or manual flush):
1. The banned user requests an OTP via WhatsApp (`POST /api/auth/otp/send`).
2. The user submits the OTP to `POST /api/auth/otp/verify`.
3. PostgreSQL is queried, but `is_banned` is not selected and not checked.
4. The server issues a valid JWT access token and refresh token.
5. Line 860 writes `user_active_session:${user.id}` with `isBanned: false`.
6. Subsequent calls to `authMiddleware` read `isBanned: false` and grant full access.

**Conclusion:** A banned user can completely bypass a ban and regain full platform access if their Redis key is evicted or cleared. When Stage 4 is authorized, fixing `POST /api/auth/otp/verify` and `POST /api/auth/token/refresh` to select `is_banned` and reject banned users before session generation must be prioritized.

---

## Section 2 — Ad-Click Flush Race Condition

### 2.1 Is the Read-Then-Reset Atomic?
**No, it is not atomic.**

In [`backend/modules/advertisements/advertisements.service.js` lines 165–187](file:///c:/Users/dhruv/AndroidStudioProjects/dating_app/backend/modules/advertisements/advertisements.service.js#L165-L187):
```javascript
async flushBufferedClicks() {
  ...
  clicks = await redis.hgetall('ad:clicks'); // [Step 1: Read snapshot]
  if (!clicks || Object.keys(clicks).length === 0) return;

  for (const [adId, countStr] of Object.entries(clicks)) {
    const count = parseInt(countStr, 10);
    if (count > 0) {
      await redis.hincrby('ad:clicks', adId, -count).catch(() => {}); // [Step 2: Decrement]
      await db.query(
        `UPDATE public.advertisements SET click_count = click_count + $1 WHERE id = $2`, // [Step 3: Write DB]
        [count, adId]
      );
    }
  }
}
```
Step 1 (`HGETALL`) and Step 2 (`HINCRBY -count`) are executed as completely separate round-trips over the network with an asynchronous iteration loop in between. There is no `GETDEL`, Lua script, or transaction wrapping them.

---

### 2.2 Behavior Under Stage 4 Multi-Instance Execution
Under Stage 4, multiple Render instances will run `AdvertisementsService` concurrently. Each instance initializes its own unref'd `setInterval(flushBufferedClicks, 5 * 60 * 1000)` on process startup.

If two instances fire their timers within the same window (e.g. within 50–200ms):
1. Suppose advertisement `ad_99` has accumulated **15 clicks** in Redis (`ad:clicks` contains `{ "ad_99": "15" }`).
2. **Instance 1** calls `HGETALL ad:clicks` and reads `count = 15`.
3. Before Instance 1 executes `HINCRBY ad:clicks ad_99 -15`, **Instance 2** calls `HGETALL ad:clicks` and also reads `count = 15`.
4. **Instance 1** executes:
   - `HINCRBY ad:clicks ad_99 -15` $\rightarrow$ Redis field `ad_99` becomes `0`.
   - `UPDATE advertisements SET click_count = click_count + 15 WHERE id = 'ad_99'` $\rightarrow$ PostgreSQL increments by 15.
5. **Instance 2** executes:
   - `HINCRBY ad:clicks ad_99 -15` $\rightarrow$ Redis field `ad_99` becomes `-15`!
   - `UPDATE advertisements SET click_count = click_count + 15 WHERE id = 'ad_99'` $\rightarrow$ PostgreSQL increments by another 15 (now +30 total).

**Concrete Consequences:**
1. **Double Counting in PostgreSQL:** The 15 actual user clicks are recorded as **30 clicks** in PostgreSQL.
2. **Negative Counter Corruption in Redis:** The Redis hash field becomes negative (`-15`). As new user clicks arrive via `HINCRBY ad:clicks ad_99 1`, the counter increases from `-15` toward `0`. The next 15 clicks will appear as non-positive numbers (`<= 0`) and will be ignored by `if (count > 0)` during future flushes, causing the next 15 clicks to be lost from PostgreSQL.
3. **No Existing Protection:** There is currently no distributed lock (`SET lock:ad_flush ... NX`), no instance leader election, and no atomic Lua script protecting this routine.

---

### 2.3 Recommendation
**Fix it before Stage 4 multi-instance deployment goes live.**

*Rationale:* While ad clicks do not represent currency (unlike user wallet balances), double-counting and negative Redis counters corrupt business analytics. Fixing this requires less than 10 lines of code using one of two standard patterns:
- **Option A (Distributed Mutex — Recommended):** Acquire a 30-second distributed lock before flushing:
  ```javascript
  const acquired = await redis.set('lock:ad_click_flush', instanceId, 'EX', 30, 'NX');
  if (!acquired) return; // Another instance is already flushing
  ```
- **Option B (Atomic Lua / Key Rename):** Atomically rename `ad:clicks` to `ad:clicks:processing:<uuid>` using `RENAME`, flush the isolated key, and delete it.

Option A is recommended for simplicity and zero impact on click ingestion.

---

## Section 3 — Multi-Instance Migration Doc Status

### 3.1 Does `backend/docs/MULTI_INSTANCE_MIGRATION.md` exist?
**Yes.** The file exists at [`backend/docs/MULTI_INSTANCE_MIGRATION.md`](file:///c:/Users/dhruv/AndroidStudioProjects/dating_app/backend/docs/MULTI_INSTANCE_MIGRATION.md) (46 lines, 5,033 bytes).

---

### 3.2 Contents Summary & Accuracy Assessment Post-Stages 1–3
The document was authored prior to the execution of Stages 1, 2, and 3. While its conceptual thesis remains valid (Socket.IO room emits work cross-instance via `@socket.io/redis-adapter`, but in-memory Maps break cross-instance lookups), large portions of the text are now **stale and inaccurate**:

1. **Stale Line References:**
   - Section 2 cites `backend/server.js#L320-L325` for `@socket.io/redis-adapter`. In the current codebase, `server.js` has 325 total lines, and the Redis adapter initialization is located at lines 215–225.
2. **Missing Stage 1 Architecture:**
   - It makes no mention of the Redis profile cache (`user:profile:${userId}`) and JWT fallback that eliminated socket-connect PostgreSQL queries.
   - It does not reflect the removal of dead billing queries in `handleCallEnd`.
3. **Missing Stage 3 Architecture:**
   - Section 1 of the doc still outlines room broadcasting broadly without reflecting the Stage 3 room collapse: `city:${city}:buddy` and `buddy:city:${city}:all` were removed and replaced by single `buddy:city:${city}:${gender}` rooms.
   - It does not account for the new `matchmaking:user_queue` reverse-lookup hash or `ad:clicks` buffering.
4. **Partial Implementation Drift:**
   - The document lists `activeInstantCalls` as an unstarted task. In reality, `instant_connect.socket.js` already contains hybrid Redis helper functions (`saveActiveInstantCall`, `getActiveInstantCall`, `deleteActiveInstantCall`), although in-memory state remains coupled to timers and socket maps.
   - Similarly, `matchmaking.socket.js` already contains prototype helpers (`saveActiveCall`, `getActiveCall`, `savePendingCall`), but they still duplicate to local `Map` objects and lack multi-instance timer coordination.

**Conclusion:** `backend/docs/MULTI_INSTANCE_MIGRATION.md` provides useful high-level context, but it is stale and should be updated or superseded by this Stage 4 design review.

---

## Section 4 — Stage 4 Redis State Schema Proposal

To safely scale the backend horizontally across multiple Render instances, all state necessary to authorize, route, and terminate calls must reside in Redis.

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                             STAGE 4 REDIS DATA MODEL                             │
├──────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│   [Direct 1:1 Call Request]           [Active Live Call (Direct or Match)]       │
│   Key: pending_call:{requestId}       Key: call:active:{callId}                  │
│   Type: String (JSON)                 Type: Hash                                 │
│   TTL: 35s                            TTL: 7200s (2 hours)                       │
│                                                                                  │
│   [VIP Instant Connect Call]          [User Call Routing Index]                  │
│   Key: instant:active:{callId}        Key: user:call:{userId}                    │
│   Type: Hash                          Type: String (callId)                      │
│   TTL: 7200s (2 hours)                TTL: 7200s (2 hours)                       │
│                                                                                  │
│   [Socket Reverse Routing]            [Distributed Call Termination Mutex]       │
│   Key: socket:call:{socketId}         Key: lock:call_end:{callId}                │
│   Type: String (callId)               Type: String ('1')                         │
│   TTL: 7200s (2 hours)                TTL: 10s                                   │
│                                                                                  │
└──────────────────────────────────────────────────────────────────────────────────┘
```

---

### 4.1 Schema Inventory & Lifecycle Specifications

#### 1. `pendingCallRequests` (Direct 1:1 Calls)
- **Problem Today:** When User A calls User B, Node 1 stores the request in local memory. If User B is connected to Node 2 and taps "Accept", Node 2 cannot find the request and fails.
- **Redis Structure:** String (JSON serialized).
- **Key Pattern:** `pending_call:{callRequestId}`
- **Payload:**
  ```json
  {
    "callRequestId": "uuid",
    "callerId": "uuid",
    "callerSocketId": "socket_id",
    "callerGender": "male",
    "targetUserId": "uuid",
    "targetGender": "female",
    "callType": "video",
    "createdAt": 1726790000000
  }
  ```
- **TTL:** **35 seconds.**
  - *Rationale:* Direct call ringing rings for 30 seconds before timing out. A 35s TTL ensures the key remains available during the final ring second while auto-purging if both clients drop offline without sending a decline event.
- **Lifecycle:**
  - *Create:* `POST /api/calls/request` or socket `call_user` generates `callRequestId`, writes `SET pending_call:{callRequestId} ... EX 35`, and sets a Redis mutex `call_lock:{callerId}` and `call_lock:{targetUserId}`.
  - *Update:* None required (pending state is immutable).
  - *Delete:* On `accept_call_request` or `decline_call_request`, the answering node calls `DEL pending_call:{callRequestId}`. If 30s expires, the initiating node or client triggers timeout and deletes the key.

---

#### 2. `activeCalls` (In-Progress 1:1 Calls & Matchmaking Calls)
- **Problem Today:** Active call metadata (participants, start time, agora channel, voice/video mode) is stored in local memory on the node that matched the call. If participant B sends `hangup` to Node 2, Node 2 cannot access duration, token records, or partner IDs.
- **Redis Structure:** Redis Hash (`HSET` / `HGETALL`).
- **Key Pattern:** `call:active:{callId}`
- **Fields:**
  | Field | Type | Description |
  | :--- | :--- | :--- |
  | `callId` | String | Unique call identifier |
  | `userA_id` | String (UUID) | User A ID |
  | `userA_gender` | String | Gender of User A |
  | `userB_id` | String (UUID) | User B ID |
  | `userB_gender` | String | Gender of User B |
  | `agoraChannelName` | String | RTC channel name |
  | `callType` | String | `'video'` or `'voice'` |
  | `startedAt` | Integer | Epoch ms when call connected |
  | `videoStartedAt` | Integer | Epoch ms when video started (null if voice) |
  | `totalVideoSeconds`| Integer | Accumulated video seconds |
  | `maxAllowedSeconds`| Integer | Daily quota cap for this call |
  | `originNodeId` | String | Instance ID that created the call |
- **TTL:** **7,200 seconds (2 hours).**
  - *Rationale:* Calls are capped well below 2 hours by daily quota limits. A 2-hour TTL guarantees that even if a server process crashes mid-call and neither client sends a hangup packet, stale active call records will not leak indefinitely or block user wallets.
- **Lifecycle:**
  - *Create:* When call is accepted or matchmaker matches, the node writes `HSET call:active:{callId}` with all fields and applies `EXPIRE call:active:{callId} 7200`.
  - *Update:* On `switch_to_voice` or `switch_to_video`, any node updates `callType`, `videoStartedAt`, and `totalVideoSeconds` using `HSET`.
  - *Delete:* On `end_call`, the terminating node retrieves fields, acquires `lock:call_end:{callId}` (to prevent double-processing), persists final duration to PostgreSQL, and calls `DEL call:active:{callId}`.

---

#### 3. `activeInstantCalls` (In-Progress VIP Instant Calls)
- **Problem Today:** VIP instant connect sessions involve coin milestone escrows (1-minute free threshold, coin payouts). While partial Redis helpers exist, milestone timers and session completion logic remain trapped in Node process memory.
- **Redis Structure:** Redis Hash (`HSET` / `HGETALL`).
- **Key Pattern:** `instant:active:{callId}`
- **Fields:**
  | Field | Type | Description |
  | :--- | :--- | :--- |
  | `callId` | String | `instant_call_{sessionId}` |
  | `sessionId` | String (UUID) | Database session ID |
  | `maleUserId` | String (UUID) | Caller ID |
  | `femaleUserId` | String (UUID) | Receiver ID |
  | `bidAmount` | Integer | Escrowed coin cost |
  | `agoraChannelName` | String | RTC channel |
  | `startedAt` | Integer | Epoch ms when connected |
  | `milestoneReached` | String | `'0'` or `'1'` (1-minute payout unlocked) |
- **TTL:** **7,200 seconds (2 hours).**
  - *Rationale:* Instant calls are governed by coin balance or 10-minute maximums. 2 hours ensures clean garbage collection if both clients disappear.
- **Lifecycle:**
  - *Create:* When female accepts, write `HSET instant:active:{callId}` and set TTL.
  - *Update:* When 1-minute milestone passes, write `HSET instant:active:{callId} milestoneReached 1`.
  - *Delete:* On hangup/disconnect, read session, finalize database coin transfer / escrow refund, and `DEL instant:active:{callId}`.

---

#### 4. `userSockets` & Reverse Call Mappings (`socketToCall`, `socketToInstantCall`)
- **Problem Today:** When a socket disconnects, the node needs to know:
  1. Did this user have an active call?
  2. If so, what was the `callId`?
  Local Maps (`socketToCall`, `socketToInstantCall`) only exist on the node holding that socket connection.
- **Proposed Solution:**
  1. **User Call Mapping (Global in Redis):**
     - Key: `user:call:{userId}` $\rightarrow$ stores `callId` (String). TTL: 7,200s.
     - Written when call starts; deleted when call ends.
     - Allows any node to check if a user is currently engaged in a call in $O(1)$.
  2. **Socket Call Attachment (Node Local):**
     - Sockets are inherently local to the Node instance holding the WebSocket TCP connection.
     - Instead of maintaining a module-level `Map()`, store `socket.activeCallId = callId` and `socket.activeCallType = 'direct' | 'instant'` directly as properties on the Socket.IO `socket` object upon connection or call acceptance.
     - When `socket.on('disconnect')` fires on that node, it reads `socket.activeCallId` directly from the socket instance with zero Map lookup overhead, and triggers the distributed hangup handler.
  3. **No `userSockets` Map Needed:**
     - In [`backend/server.js`](file:///c:/Users/dhruv/AndroidStudioProjects/dating_app/backend/server.js#L242), every socket auto-joins `socket.join(socket.userId)`.
     - To emit to any user anywhere in the cluster, execute:
       ```javascript
       io.to(targetUserId).emit('event_name', payload);
       ```
     - The `@socket.io/redis-adapter` handles cross-instance packet dispatch via Redis Pub/Sub in $O(1)$. Maintaining a separate `userSockets` mapping of user IDs to socket IDs is redundant and should be removed.

---

### 4.2 Distributed Call Termination & Mutex Protection
To guarantee that two simultaneous hangup requests (e.g. User A hangs up on Node 1 while User B disconnects on Node 2) do not double-bill, double-refund, or corrupt PostgreSQL records, Stage 4 will enforce a distributed lock on the end-call path:

```javascript
async function endCallDistributed(io, redis, callId, reason) {
  // Acquire 10s atomic termination mutex
  const lockKey = `lock:call_end:${callId}`;
  const acquired = await redis.set(lockKey, '1', 'EX', 10, 'NX');
  if (!acquired) {
    // Another instance is already processing termination for this call
    return;
  }

  try {
    const callData = await redis.hgetall(`call:active:${callId}`);
    if (!callData || Object.keys(callData).length === 0) return;

    // Persist duration and transactions to PostgreSQL...
    await callsService.recordCallCompletion(callData, reason);

    // Clean up Redis state
    await Promise.all([
      redis.del(`call:active:${callId}`),
      redis.del(`user:call:${callData.userA_id}`),
      redis.del(`user:call:${callData.userB_id}`),
      redis.del(`call_lock:${callData.userA_id}`),
      redis.del(`call_lock:${callData.userB_id}`),
    ]);

    // Notify participants across all instances via user rooms
    io.to(callData.userA_id).emit('call_ended', { callId, reason });
    io.to(callData.userB_id).emit('call_ended', { callId, reason });
  } finally {
    await redis.del(lockKey).catch(() => {});
  }
}
```

---

### 4.3 Operational Scenarios

#### Scenario 1: Instance Restart Mid-Call
*Context: An active call is in progress between User A (connected to Node 1) and User B (connected to Node 2). Node 1 crashes or is redeployed by Render.*

1. **State in Redis:**
   - The call record `call:active:{callId}` remains intact in Redis with its TTL.
   - `user:call:{userA}` and `user:call:{userB}` remain set.
2. **Audio/Video Media Layer (Agora):**
   - The media stream flows peer-to-peer or through Agora RTC SD-RTN servers, **not through Node.js**.
   - User A and User B can physically continue hearing/seeing each other for several seconds even while Node 1 is offline.
3. **Socket.IO Signaling Layer:**
   - User A's WebSocket TCP connection drops. User A's mobile client immediately enters Socket.IO reconnect mode.
4. **Reconnection & State Recovery Proposal:**
   - When User A reconnects, Render's load balancer routes them to any available instance (e.g. Node 2 or a newly spawned Node 1).
   - During the handshake, Node 2 authenticates User A and reads `user:call:{userA.id}` from Redis.
   - If `user:call:{userA.id}` exists:
     - Node 2 reads `call:active:{callId}`.
     - If the call is still valid, Node 2 emits `call_reconnected` to User A with current channel and elapsed time, restoring signaling synchronization without aborting the call.
   - **Timeout Safety Net:** If User A does not reconnect within **15 seconds**, Node 2 (which detects User A's absence via an Agora RTC user-offline callback or signaling ping timeout) triggers `endCallDistributed(callId, 'peer_timeout')`, ending the call cleanly in PostgreSQL and notifying User B.

---

#### Scenario 2: Split-Brain Mitigation During Rollout
*Context: During a rolling deployment on Render, Node 1 runs the new Redis-backed code while Node 2 still runs the old in-memory Map code.*

**Risk:** If User A (on new Node 1) calls User B (on old Node 2), Node 1 writes to Redis, but Node 2 looks in its local JavaScript Map and fails to answer.

**Evaluation of Approaches:**
1. *Feature Flagging:* Adds substantial branching complexity across socket event handlers.
2. *Rolling Deploy without Coordination:* High risk of failed call attempts during the 2–3 minute deploy window.
3. *Brief Maintenance Cutover (Recommended):*
   - **Deployment Strategy:** Set Render deployment strategy to deploy new instances and perform a clean cutover.
   - **Pre-Deploy Safety Guard:** Deploy the new code during a scheduled low-traffic window. Since WebSockets churn rapidly on mobile, any call in flight during the exact deploy moment will terminate via normal socket disconnect cleanup.
   - **Backward-Compatible Redis Fallback:** In the new code, keep a defensive fallback: if a request arrives on the new node, write to **both** local memory and Redis; if reading, check local memory first, then Redis. This ensures that even during a brief 60-second rolling window, calls can resolve across mixed nodes.

---

## Verification & Guardrail Checklist Before Stage 4

- [ ] User review and explicit approval of this document.
- [ ] Fix ban status durability in `POST /api/auth/otp/verify` and `POST /api/auth/token/refresh` (identified in Section 1).
- [ ] Add distributed mutex to `flushBufferedClicks()` in `advertisements.service.js` (identified in Section 2).
- [ ] Implement Redis Hash schema for `activeCalls` and `pendingCallRequests` in `matchmaking.socket.js`.
- [ ] Execute two-node local cluster test (`PORT=3001` and `PORT=3002`) verifying direct call handshake and hangup across process boundaries.

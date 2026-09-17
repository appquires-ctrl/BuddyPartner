# Multi-Instance Horizontal Scaling & Redis Migration Plan

## Executive Summary
The backend currently attaches `@socket.io/redis-adapter` in [`server.js`](file:///c:/Users/dhruv/AndroidStudioProjects/dating_app/backend/server.js), which successfully broadcasts room events (`io.to(userId).emit(...)`, `io.to(room).emit(...)`) across multiple server instances.

However, **call state and session authorization** rely on plain JavaScript `Map()` objects residing in single-process memory. Before horizontally scaling beyond **1 Node.js instance** (e.g. deploying 2+ replicas on Render, Railway, or AWS ECS), these in-memory Maps must be transitioned to Redis as detailed below.

---

## 1. Inventory of In-Memory Maps & Migration Matrix

| In-Memory Map | Location | Purpose | Priority | Proposed Redis Architecture |
| :--- | :--- | :--- | :--- | :--- |
| `activeCalls` | [`matchmaking.socket.js`](file:///c:/Users/dhruv/AndroidStudioProjects/dating_app/backend/modules/matchmaking/matchmaking.socket.js) | Stores `{ userA: { userId, socketId, gender }, userB: { ... } }` for live calls | **CRITICAL (Must Move)** | **Redis Hash** `call:{callId}` with field values serialized as JSON, TTL: 24h. Allows any node receiving hangup/heartbeat to validate call participants. |
| `pendingCallRequests` | [`matchmaking.socket.js`](file:///c:/Users/dhruv/AndroidStudioProjects/dating_app/backend/modules/matchmaking/matchmaking.socket.js) | Stores pending direct call request metadata (`callerId`, `targetUserId`, `timer`) | **CRITICAL (Must Move)** | **Redis String/Hash** `pending_call:{callRequestId}` with 35s TTL. When recipient answers on Node 2, Node 2 fetches call state from Redis. |
| `activeInstantCalls` | [`instant_connect.socket.js`](file:///c:/Users/dhruv/AndroidStudioProjects/dating_app/backend/modules/instant_connect/instant_connect.socket.js) | Stores live VIP instant call state, `maleUserId`, `femaleUserId`, `sessionId` | **CRITICAL (Must Move)** | **Redis Hash** `instant:active_call:{callId}` with TTL. Authorizes milestones and hangups across all nodes. |
| `socketToCall` / `socketToInstantCall` | Both socket files | Reverse mapping from `socket.id` to `callId` for disconnects | **MEDIUM** | Replace with socket session attachment `socket.activeCallId = callId`, plus Redis key `user_call:{userId} -> callId`. |
| `userSockets` | Both socket files | Maps `userId -> socket.id` | **LOW (Already Solved by Rooms)** | **No Redis Map Needed.** Sockets auto-join `socket.userId` on connect. `io.to(userId).emit(...)` uses the Redis adapter to route to the user's socket across instances in $O(1)$. |
| `ringingTimers` / `surgeTimers` | [`instant_connect.socket.js`](file:///c:/Users/dhruv/AndroidStudioProjects/dating_app/backend/modules/instant_connect/instant_connect.socket.js) | In-memory `setTimeout` handles for 15s ringing and 30s FCM surge cascades | **LOW (Safe to Keep Local for Now)** | Safe to leave in-memory on the initiating node. If the node crashes, the safety-net ticker or client-side timeout recovers the state. For enterprise scale, can use Redis Key Expiry Notifications (`__keyevent@0__:expired`). |

---

## 2. Why Room Emits Already Work Across Instances
In [`backend/server.js`](file:///c:/Users/dhruv/AndroidStudioProjects/dating_app/backend/server.js#L320-L325), the `@socket.io/redis-adapter` is initialized. When user `123` connects, they join room `123`. 
* If Instance 1 executes `io.to('456').emit('incoming_call_request', payload)`, the Redis adapter publishes to Redis pub/sub.
* Instance 2 receives the pub/sub packet and delivers it directly to User `456`'s socket.
* **The danger is NOT packet delivery; the danger is state lookup.** When User `456` clicks "Accept" and sends `accept_call_request` to Instance 2, Instance 2 checks its local `pendingCallRequests.has(callRequestId)` Map, finds nothing, and returns "Call request not found or expired".

---

## 3. Step-by-Step Implementation Roadmap

### Phase 1: Shared Call State in Redis (Estimated: 2 Days)
1. In `matchmaking.socket.js`, write `savePendingCall(callRequestId, data)` writing to `redis.set('pending_call:' + callRequestId, JSON.stringify(data), 'EX', 35)`.
2. In `accept_call_request`, retrieve the request from Redis with `redis.get('pending_call:' + callRequestId)`.
3. In `activeCalls`, migrate reads and writes to `redis.hset('active_call:' + callId, ...)` and `redis.hgetall('active_call:' + callId)`.

### Phase 2: Instant Connect VIP Shared State (Estimated: 1 Day)
1. Store claimed instant sessions in `redis.set('instant:active_call:' + callId, ...)` instead of `activeInstantCalls.set(...)`.
2. Enable multi-instance end-call authorization via Redis key lookup.

### Phase 3: Validation & Chaos Testing (Estimated: 1 Day)
1. Run two separate server processes locally on port 3001 and port 3002 connected to the same Redis and database.
2. Connect Client A to 3001 and Client B to 3002.
3. Validate complete matchmaking, ringing, answering, Agora token exchange, and hangup across the process boundary.

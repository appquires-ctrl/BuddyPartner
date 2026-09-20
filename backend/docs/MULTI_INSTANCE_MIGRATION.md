# Multi-Instance Horizontal Scaling & Redis Migration (COMPLETED)

## Executive Summary
**Status: Fully Implemented & Cluster Verified (September 2026)**

All single-process in-memory call state `Map()` structures have been completely eradicated from the backend codebase. The backend now runs as an horizontally scalable, stateless cluster backed by Neon PostgreSQL, Upstash/Cloud Redis, and the `@socket.io/redis-adapter`. Live two-node cluster testing across ports 3001 and 3002 verified zero state loss for cross-node call initiation, answering, mid-call state reading, atomic hangup, and cross-node reconnection recovery.

---

## 1. Eradication of In-Memory Maps

The following in-memory maps were completely removed and replaced with distributed Redis services:

| Deprecated In-Memory Map | Former Location | Replacement Architecture | Status |
| :--- | :--- | :--- | :--- |
| `activeCalls` | `matchmaking.socket.js` | Distributed Redis Hash `call:active:{callId}` (TTL: 7200s) + `user:call:{userId}` lookup | **DELETED** |
| `pendingCallRequests` | `matchmaking.socket.js` | Distributed Redis String `pending_call:{callRequestId}` (TTL: 35s) | **DELETED** |
| `activeInstantCalls` | `instant_connect.socket.js` | Distributed Redis Hash `instant:active:{callId}` (TTL: 7200s) + `user:call:{userId}` | **DELETED** |
| `socketToCall` / `socketToInstantCall` | Both socket files | Socket instance property (`socket.activeCallId`) + Redis `user:call:{userId}` reverse index | **DELETED** |
| `userSockets` | Both socket files, `server.js` | Redis-backed `PresenceService.isUserOnline` and Socket.io Personal Rooms (`io.to(userId)`) | **DELETED** |

Verification: `git grep` confirms 0 matches for `activeCalls`, `pendingCallRequests`, `activeInstantCalls`, `socketToCall`, `socketToInstantCall`, and `userSockets` across all JavaScript source files in the backend.

---

## 2. Distributed Redis State Schema

### Call State Keys
- **`pending_call:{callRequestId}`** (String, JSON, TTL 35s):
  Stores `{ callRequestId, callerId, callerGender, targetUserId, targetGender, callType, createdAt }`.
- **`user:pending_call:{targetUserId}`** (String, TTL 35s):
  Maps target user to current incoming `callRequestId` for fast $O(1)$ busy checks.
- **`call:active:{callId}`** (Hash, TTL 7200s):
  Fields: `callId`, `userA_id`, `userA_gender`, `userB_id`, `userB_gender`, `agoraChannelName`, `callType`, `startedAt`, `voiceStartedAt`, `videoStartedAt`, `totalAudioSeconds`, `totalVideoSeconds`, `maxAllowedSeconds`, `originNodeId`.
- **`instant:active:{callId}`** (Hash, TTL 7200s):
  Fields: `callId`, `sessionId`, `maleUserId`, `femaleUserId`, `agoraChannelName`, `bidAmount`, `callType`, `startedAt`, `voiceStartedAt`, `videoStartedAt`, `totalAudioSeconds`, `totalVideoSeconds`, `originNodeId`.
- **`user:call:{userId}`** (String, TTL 7200s):
  Maps any engaged participant directly to their active `callId` ($O(1)$ lookup for disconnects and incoming call blocking).
- **`call_lock:{userId}`** (String, TTL 7200s):
  Cluster-wide flag (`'1'`) preventing concurrent call initiation or queue entrance.
- **`peer_disconnect_timer:{callId}:{userId}`** (String, TTL 15s):
  Tracks the 15-second reconnection grace period when a peer drops abruptly.

### Master Redis Call & Presence Reference Table

| Key Name Pattern | Redis Type | TTL | Purpose & Lifecycle |
| :--- | :--- | :--- | :--- |
| `call:active:{callId}` | Hash | 7200s (2h) | Active direct/matchmaking call state (14 fields: participant IDs, Agora channel, timestamps, elapsed audio/video seconds, origin node). Purged on hangup. |
| `instant:active:{callId}` | Hash | 7200s (2h) | Active VIP instant call session state (male/female IDs, bid, Agora channel, milestones). Purged on hangup. |
| `pending_call:{callRequestId}` | String (JSON) | 35s | Transient pending direct call request metadata. Purged when call is answered, declined, cancelled, or times out. |
| `user:pending_call:{targetUserId}` | String | 35s | Target user mapping to active incoming `callRequestId` for $O(1)$ busy checks. Purged when call is answered, declined, or times out. |
| `user:call:{userId}` | String | 7200s (2h) | Participant-to-call reverse index. Enables instant call recovery on socket reconnect and fast $O(1)$ busy detection. Purged on call end. |
| `call_lock:{userId}` | String | 7200s (2h) | Mutual exclusion flag (`'1'`) preventing concurrent call initiation or queue entrance while in call. Purged on call end. |
| `peer_disconnect_timer:{callId}:{userId}` | String | 15s | 15-second grace period countdown when a peer abruptly drops. Deleted on reconnect recovery or triggers call end on expiry. |
| `lock:call_end:{callId}` | String (Mutex) | 10s (NX) | Distributed mutex lock preventing duplicate execution of call termination logic across multiple cluster instances. |
| `lock:ad_click_flush` | String (Mutex) | 30s (NX) | Distributed mutex lock ensuring only one node flushes buffered ad clicks to Postgres per 5-minute interval. |
| `online_sockets:{userId}` | Set | 90s (Lease) | Set of active socket IDs for user presence. Refreshed every 45s on client heartbeat. Key deleted when count reaches 0 after 1.5s debounce. |
| `direct_mutex:{userId}` | String (Mutex) | 5s (NX) | Short-lived lock preventing race conditions when two users call each other at the exact same millisecond. |
| `call_quota:{userId}:{yearMonth}:audio_seconds` | String (Integer) | 40 days | Cumulative monthly audio call duration counter (sub-ms `INCRBY`). Enforces 200 min/mo telecom fair-use cap. |
| `call_quota:{userId}:{yearMonth}:video_seconds` | String (Integer) | 40 days | Cumulative monthly video call duration counter (sub-ms `INCRBY`). Enforces 60 min/mo telecom fair-use cap. |
| `instant:female_pool` | Set | Persistent | Pool of female user IDs eligible to receive instant connect calls. Female removed when in-call or toggled offline. |
| `instant:ringing:{femaleId}` | String | 15s | Transient lock marking a female as currently ringing for a dispatched instant call. |
| `instant:claim_session:{sessionId}` | String (Mutex) | 15s (NX) | Atomic lock determining the winning female responder for a broadcast instant connect session. |

---

## 3. Disconnection & Reconnection Architecture

1. **Abrupt Peer Disconnection**:
   - When a user's socket disconnects during an active call, Node 1 sets `peer_disconnect_timer:{callId}:{userId}` in Redis with a 15-second TTL.
   - Node 1 dispatches `call_peer_disconnected` cluster-wide to the other participant's personal room via `io.to(otherUserId)`.
2. **Reconnection Recovery**:
   - If the disconnected user reconnects to **any node in the cluster** (e.g. Node 2) within 15 seconds, the socket handshake automatically detects their active call via `user:call:{userId}`.
   - Node 2 deletes the grace timer, restores `socket.activeCallId`, and emits `call_reconnected` with elapsed seconds and channel metadata to the reconnected user.
   - Node 2 emits `call_peer_reconnected` to the other participant, resuming the session with zero data loss.
3. **Grace Expiration**:
   - If the 15-second grace timer expires without reconnection, `distributedCallService.endCallDistributed` terminates the call cluster-wide with reason `'peer_timeout'`.

---

## 4. Live Multi-Instance Cluster Verification Evidence

Automated two-node cluster test (`backend/scripts/verify_stage4_cluster.js`):
- **Node 1**: `http://localhost:3001`
- **Node 2**: `http://localhost:3002`
- **Client A**: Connected to Node 1 (`f19e023a-b413-4bb3-9079-dc9340e794f0`)
- **Client B**: Connected to Node 2 (`b4bf9bb3-749d-42a6-9085-3ccd366b2c00`)

### Verification Log Summary:
```
Step 1: Starting Node 1 on port 3001, Node 2 on port 3002...
✅ Node 1 active on http://localhost:3001
✅ Node 2 active on http://localhost:3002

Step 2: Connecting Client A to Node 1 and Client B to Node 2...
✅ Client A (User: John Doe) connected to Node 1
✅ Client B (User: Kiran Soni) connected to Node 2

Step 3: Client A on Node 1 initiating direct_call to Client B on Node 2...
✅ Client B on Node 2 received incoming_call_request via Redis Adapter!
   Redis pending_call TTL: 35s
✅ Redis pending_call:* verified with distributed TTL.

Step 4: Client B on Node 2 accepting call request...
✅ Both clients received match_found!
   Call ID: 823b23d0-e2a3-44df-80c2-6f6fb1d70604

Step 5: Verifying distributed call state schema in Redis...
   call:active:* Hash fields verified: 14 fields present
✅ call:active:{callId} Hash, user:call:* mappings, and call_lock:* verified in Redis.

Step 6: Reading call state via distributedCallService.getActiveCall...
✅ Mid-call state read verified successfully.

Step 7: Client A on Node 1 ending call, Client B on Node 2 receiving call_ended...
✅ Client B on Node 2 received call_ended event: reason=manual
✅ All Redis keys atomically cleaned up after distributed call termination.

Step 8: Testing Reconnection Recovery across instances...
   Disconnecting Client A from Node 1...
✅ Client B on Node 2 received call_peer_disconnected! graceSeconds=15
✅ peer_disconnect_timer verified in Redis with 15s expiration.
   Reconnecting User A to Node 2 (http://localhost:3002)...
✅ User A successfully reconnected on Node 2 and recovered active call!
   Recovered callId: 16645307-9271-4b0a-aa12-a4928aacc4ec
✅ Reconnection test passed cleanly.

Step 9: Testing distributed lock on flushBufferedClicks...
   Acquired lock:ad_click_flush manually in Redis
✅ flushBufferedClicks safely skipped when distributed lock is active on another node.
   Released lock:ad_click_flush

================================================================
🎉 ALL STAGE 4 MULTI-INSTANCE CLUSTER TESTS PASSED SUCCESSFULLY!
================================================================
```
Result: **Exit Code 0 — All cluster tests passed.**


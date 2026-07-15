# LoopCall — Implement Matchmaking (Redis + Socket.io + Agora)

Paste into your code-generation tool. Builds on the completed auth implementation and the **already-built Flutter matchmaking UI** (button → waiting screen → connected call screen with Mute/End Call/Speaker/Switch-to-Video, as shown in the reference screenshot). This pass is about **wiring real logic behind that existing UI**, not building new screens.

---

## 1. Decisions locked in for this pass

- **Call duration:** hard 5-minute cap, no extension, no coins involved. Call force-ends at 5:00.
- **Video upgrade:** free, no coin cost, during Phase 1.
- **Post-call:** call ends → user returns straight to the home screen. No rating/report interstitial for this pass.
- **Follow button:** UI-only stub. Tapping it should not error, but no backend follows table/logic yet — wire it to a no-op or a "coming soon" toast.
- **Message button:** UI-only stub for this pass, same treatment as Follow — no navigation, no backend call. Messaging is a separate future prompt; keep this pass fully focused on matchmaking.
- **Location ("Mumbai, India") and verified badge:** not in the schema. Hide these UI elements (or leave hardcoded placeholder text) rather than wiring them to real data — do not add new columns for this pass.

---

## 2. Backend — Node.js/Express additions

### New dependencies
- `ioredis` (Redis client)
- `socket.io` (server)
- `agora-access-token` (Agora token generation)

### `modules/matchmaking/`
- `matchmaking.service.js` — queue logic:
  - `joinQueue(userId, socketId)` — push user into a Redis list/set representing "waiting users"
  - Matching worker: whenever 2+ users are in the queue, atomically pop two and pair them (use a Redis `WATCH`/`MULTI` transaction or a Lua script to avoid race conditions when many users queue simultaneously — this is the part that must be safe under concurrent load)
  - `leaveQueue(userId)` — remove from queue (user cancels while waiting)
- `matchmaking.socket.js` — Socket.io event handlers:
  - `join_queue` (client → server) — adds user to Redis queue
  - `match_found` (server → both clients) — emitted once paired, payload includes: `callId`, `agoraChannelName`, `agoraToken`, matched user's public info (name/avatar only — nothing beyond what's already in `public.users`)
  - `leave_queue` (client → server)
  - `call_ended` (server → both clients) — emitted on timer expiry or if either party ends the call
  - `upgrade_to_video` (client → server → other client) — relays the upgrade request/acceptance between both parties

### `modules/calls/`
- `calls.service.js`:
  - `createCall(userAId, userBId)` — inserts a row into `calls` (status `active`, type `voice`, `started_at = now()`)
  - `generateAgoraToken(channelName, uid)` — uses your Agora App ID + App Certificate (env vars, never client-exposed) to mint a short-lived RTC token
  - `endCall(callId)` — sets `status = ended`, `ended_at = now()`, computes `duration_seconds`
  - `upgradeToVideo(callId)` — updates `calls.type = video` (or logs a separate upgrade timestamp, your call)
- Server-side **authoritative 5-minute timer**: do not trust the Flutter client's countdown alone — the backend should also force-end the call at 5:00 (e.g. a delayed job or `setTimeout` tied to the call record) so a modified/compromised client can't extend it. Emit `call_ended` to both sockets when this fires.

### Database (SQL — add to your existing schema)
```sql
CREATE TABLE IF NOT EXISTS public.calls (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  caller_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  matched_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  status TEXT CHECK (status IN ('active', 'ended')) NOT NULL DEFAULT 'active',
  call_type TEXT CHECK (call_type IN ('voice', 'video')) NOT NULL DEFAULT 'voice',
  duration_seconds INTEGER,
  started_at TIMESTAMPTZ DEFAULT NOW(),
  ended_at TIMESTAMPTZ
);
ALTER TABLE public.calls ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own calls"
  ON public.calls FOR SELECT USING (auth.uid() = caller_id OR auth.uid() = matched_user_id);
-- No client-side INSERT/UPDATE — calls are only written by the Node backend's service-role client.
```

### Env vars to add
`REDIS_URL`, `AGORA_APP_ID`, `AGORA_APP_CERTIFICATE`

---

## 3. Flutter — wiring into the existing UI (no new screens)

- `application/matchmaking_controller.dart` (Riverpod) — connects to your Socket.io server on `join_queue` tap, listens for `match_found`, navigates from the waiting UI to the existing connected-call UI on receipt
- On `match_found`, initialize the **Agora RTC engine** using the `agoraToken`/`agoraChannelName` from the payload, join the channel in audio-only mode
- Wire the existing countdown UI (`04:32` display in your screenshot) to count down from 5:00 **client-side for display purposes only** — actual call termination is driven by the server's `call_ended` event, not the client's local timer, to stay consistent with the backend being authoritative
- "Switch to Video Call" button emits `upgrade_to_video`; on the other party's acceptance, re-join the Agora channel with video enabled (or enable local video track if already joined in a video-capable mode)
- "End Call" button emits a manual end-call event, same cleanup path as the server-driven `call_ended`
- On call end (either path), navigate back to the home screen — no interstitial
- "Follow" button — wire to a no-op/toast, not a real backend call
- "Message" button — UI-only stub for this pass, no navigation or backend call

---

## 4. Things to verify before shipping this pass

- **Queue fairness under load** — test with many simulated concurrent `join_queue` calls to confirm no user gets stuck waiting indefinitely due to a race in the pairing logic
- **Disconnect handling** — if one user's socket drops mid-call (app killed, network loss), the other user needs to be notified and returned to home, not left in a dead call. Handle Socket.io's `disconnect` event to trigger `call_ended` for the remaining party.
- **Duplicate queue entries** — a user tapping "Matchmaking" twice quickly shouldn't end up double-queued or matched with themselves
- **Agora token expiry** — tokens should be short-lived (scoped to roughly the call duration + buffer), not long-lived credentials


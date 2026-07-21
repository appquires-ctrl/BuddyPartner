# LoopCall — Implement Messaging / Chat

Paste into your code-generation tool. Builds on completed Auth and Matchmaking. Reuses the existing Socket.io server/connection from matchmaking — do not stand up a second real-time system.

---

## 1. Decisions locked in for this pass

- **Who can message whom:** open — any authenticated user can start a conversation with any other user. No restriction to matched/called users only, no follow requirement.
- **Call screen "Message" button:** wire it now — tapping it on `active_call_page.dart` finds-or-creates a conversation with the matched user and navigates to the chat screen.
- **Transport:** Socket.io (same server/connection as matchmaking) — no Supabase Realtime, no Firebase Firestore/Realtime DB (Firebase is used for Auth only in this project), no second real-time provider.
- **Storage:** Postgres (Neon) is source of truth, written first, then broadcast. Media attachments are **deferred for this pass** — text-only messaging, no storage provider chosen yet (see project context Section 3).
- **Given "open" messaging is the highest-abuse-risk option of the three choices, block/report enforcement in Section 4 is not optional for this pass** — build it alongside the core chat, not after.

---

## 2. Database (SQL — Neon Postgres, add to existing schema)

> **Stack note:** this project moved from Supabase to Neon + Firebase Auth (see project context Section 3). `users.id` is a `TEXT` column holding the Firebase UID, not a Postgres-generated UUID. There is no Row Level Security here — Neon has no `auth.uid()` session context. **All access control below is enforced entirely in Node backend query logic**, not the database.

```sql
CREATE TABLE IF NOT EXISTS public.conversations (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_a_id TEXT REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  user_b_id TEXT REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  last_message_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (user_a_id, user_b_id)
);
-- Enforce a single canonical row per pair regardless of who initiated:
-- always store user_a_id < user_b_id (string comparison on the Firebase UID) when inserting,
-- so (A,B) and (B,A) can never both exist as separate rows.

CREATE TABLE IF NOT EXISTS public.messages (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE NOT NULL,
  sender_id TEXT REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  content TEXT,
  media_url TEXT,
  type TEXT CHECK (type IN ('text', 'image', 'system')) NOT NULL DEFAULT 'text',
  status TEXT CHECK (status IN ('sent', 'delivered', 'read')) NOT NULL DEFAULT 'sent',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.message_reads (
  conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE NOT NULL,
  user_id TEXT REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  last_read_message_id UUID REFERENCES public.messages(id),
  PRIMARY KEY (conversation_id, user_id)
);

-- No RLS, no policies — Neon has no session-based auth.uid(). Every query below must be
-- written to explicitly filter by the requesting user's Firebase UID (from the verified
-- token in auth.middleware.js), enforced in application code, not the database.
-- No client-side INSERT on messages/conversations — all writes go through the Node backend,
-- so the backend can enforce the block-list check (Section 4) before any message is stored.
```

Index for pagination: `CREATE INDEX idx_messages_conversation_created ON public.messages (conversation_id, created_at DESC);`

---

## 3. Backend — Node.js/Express additions

### `modules/messaging/`
- `messaging.service.js` — every function here must take the requesting user's **verified Firebase UID** (from `auth.middleware.js`) and use it to scope queries — this is now the *only* access control layer, since there's no RLS:
  - `findOrCreateConversation(userAId, userBId)` — normalizes ordering (lexicographically smaller Firebase UID = `user_a_id`) before insert/lookup so no duplicate conversation rows are created
  - `sendMessage(conversationId, senderId, content, type, mediaUrl)` — **checks the block list first (Section 4)**, then inserts into `messages`, updates `conversations.last_message_at`, returns the inserted row
  - `getMessages(conversationId, requestingUserId, cursor, limit)` — cursor-based pagination (by `created_at`/`id`, not offset); **must verify `requestingUserId` is one of the two participants before returning any rows** — this replaces what RLS used to guarantee automatically
  - `getConversations(userId)` — list with last message preview + unread count (join against `message_reads`), scoped to `WHERE user_a_id = $userId OR user_b_id = $userId`
  - `markAsRead(conversationId, userId, messageId)` — upserts `message_reads`
- `messaging.socket.js`:
  - `send_message` (client → server) — calls `sendMessage()`, then emits `message:new` to both participants' sockets
  - `typing` (client → server → other participant)
  - `message:read` (client → server) — calls `markAsRead()`, emits read-receipt update to the sender
- REST endpoints (history/fallback, not live delivery):
  - `GET /conversations`
  - `GET /conversations/:id/messages?cursor=&limit=`
  - `POST /conversations/:id/messages` (fallback path if socket isn't connected)

### Media
- **Deferred for this pass.** No storage provider is chosen yet (Supabase Storage no longer applies). Ship text-only messaging (`type = 'text'`) now; `media_url` and `type = 'image'` stay in the schema for forward compatibility but aren't wired to any upload path yet. Revisit once a storage provider (S3, R2, or similar) is picked.

---

## 4. Safety — required for this pass, not optional

Since messaging is open (any user → any user), build these alongside the chat itself:

- **Block list:** add a `public.blocks` table (`blocker_id TEXT`, `blocked_id TEXT` — both referencing `public.users(id)`, `created_at`, composite unique). Before `sendMessage()` inserts anything, check: has either party blocked the other? If so, reject server-side with a clear error — do not silently drop it client-side only, since a client-only block is trivially bypassed.
- **Report tie-in:** the `reports` table already exists in your schema — add a "report message" action from the chat UI that references a specific `message_id`/`conversation_id`.
- **Rate limiting:** apply a send-rate limit per user (e.g. via a simple Redis counter, since Redis is already in your stack from matchmaking) to prevent spam/harassment floods — a few messages per second cap is enough to stop abuse without affecting normal use.

---

## 5. Flutter — new feature folder `features/chat/`

- `presentation/pages/conversations_list_page.dart` — list of conversations, last message preview, unread badge, reuses `AppCard`/`AppEmptyState` from the design system
- `presentation/pages/chat_page.dart` — message thread, reuses existing design tokens; input bar with a send button (no attach-image button for this pass — media is deferred, see Section 3)
- `application/chat_controller.dart` (Riverpod) — connects to the **existing Socket.io connection** (don't open a second connection; reuse the one from matchmaking), listens for `message:new`, `typing`, `message:read`
- `application/conversations_provider.dart` — fetches conversation list via REST, updates on new-message socket events
- Wire **`active_call_page.dart`'s "Message" button**: on tap, call `findOrCreateConversation(currentUserId, matchedUserId)` (via the messaging REST/socket layer), then `context.push` to `chat_page.dart` with the resulting `conversationId`
- Add a **Block** and **Report** action (e.g. from a chat overflow menu) wired to the backend endpoints from Section 4 — build this in the same pass as the chat UI itself, not deferred

---

## 6. Things to verify before shipping this pass

- Sending a message to a user who has blocked you (or vice versa) is rejected server-side, not just hidden in the UI
- Two conversation rows are never created for the same pair regardless of who messages first (test both directions)
- Pagination works correctly with cursor-based queries on a conversation with a large message history (don't just test with 5 messages)
- Rate limiter actually triggers under rapid repeated sends, and gives the sender a clear "slow down" response rather than silently dropping messages
- Message delivery still works correctly if the recipient is offline when sent (should appear on their next `getConversations`/`getMessages` fetch, not be lost)

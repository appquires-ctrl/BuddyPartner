-- match.lua
-- Atomically pops two members from a Redis sorted set (the matchmaking queue).
-- Returns the two members if available, or nil if fewer than 2 are queued.
--
-- KEYS[1] = queue key (e.g. "matchmaking:queue")
-- Returns: { userId1, socketId1, userId2, socketId2 } or empty table

local queueKey = KEYS[1]

-- Check if at least 2 members are in the queue
local count = redis.call('ZCARD', queueKey)
if count < 2 then
  return {}
end

-- Pop the two oldest members (lowest score = earliest timestamp)
-- ZPOPMIN returns { member1, score1, member2, score2 }
local popped = redis.call('ZPOPMIN', queueKey, 2)

if #popped < 4 then
  -- Race condition safety: if somehow we got fewer than 2, push them back
  for i = 1, #popped, 2 do
    redis.call('ZADD', queueKey, popped[i + 1], popped[i])
  end
  return {}
end

-- popped = { member1, score1, member2, score2 }
-- Each member is stored as "userId:socketId"
return { popped[1], popped[3] }

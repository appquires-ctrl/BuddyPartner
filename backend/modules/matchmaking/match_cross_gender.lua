-- match_cross_gender.lua
-- Atomically pops one member from the male queue and one from the female queue.
-- Returns the two members if both queues have at least 1 entry, or empty table otherwise.
--
-- KEYS[1] = male queue key (e.g. "queue:male")
-- KEYS[2] = female queue key (e.g. "queue:female")
-- Returns: { maleMember, femaleMember } or empty table

local maleQueue = KEYS[1]
local femaleQueue = KEYS[2]

-- Check if both queues have at least 1 member
local maleCount = redis.call('ZCARD', maleQueue)
local femaleCount = redis.call('ZCARD', femaleQueue)

if maleCount < 1 or femaleCount < 1 then
  return {}
end

-- Pop the oldest member from each queue
-- ZPOPMIN returns { member, score }
local malePopped = redis.call('ZPOPMIN', maleQueue, 1)
local femalePopped = redis.call('ZPOPMIN', femaleQueue, 1)

-- Verify we got both
if #malePopped < 2 or #femalePopped < 2 then
  -- Race condition safety: push back any popped members
  if #malePopped >= 2 then
    redis.call('ZADD', maleQueue, malePopped[2], malePopped[1])
  end
  if #femalePopped >= 2 then
    redis.call('ZADD', femaleQueue, femalePopped[2], femalePopped[1])
  end
  return {}
end

-- malePopped = { member, score }, femalePopped = { member, score }
-- Each member is "userId:socketId"
return { malePopped[1], femalePopped[1] }

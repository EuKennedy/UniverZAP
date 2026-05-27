# Atomic dedup lock for WhatsApp incoming messages.
#
# Meta and WAHA both deliver the same webhook event multiple times. This
# lock uses Redis SET NX EX to ensure only one worker processes a given
# source_id at the same instant. The lock is short-lived on purpose:
# the long-term dedup is `Message.find_by(source_id: …)` against the DB.
# Once a message row exists the next concurrent webhook returns early
# before even attempting to acquire the lock again, so we don't need a
# day-long TTL.
class Whatsapp::MessageDedupLock
  KEY_PREFIX = Redis::RedisKeys::MESSAGE_SOURCE_KEY
  # 60s is generous for the worst-case happy path (media download +
  # contact creation + conversation set up + message persist). Anything
  # left over after that window almost certainly crashed and the lock
  # MUST expire so the retry can take over — keeping a 24h TTL here is
  # how messages permanently disappeared in production after a deploy
  # that aborted mid-process.
  DEFAULT_TTL = 60

  def initialize(source_id, ttl: DEFAULT_TTL)
    @key = format(KEY_PREFIX, id: source_id)
    @ttl = ttl
  end

  # Returns true when the lock is acquired (caller should proceed).
  # Returns false when another worker already holds the lock.
  def acquire!
    ::Redis::Alfred.set(@key, true, nx: true, ex: @ttl)
  end

  # Manual release for the "we acquired the lock then the persist
  # raised" branch. After we drop the lock the next retry (Sidekiq or
  # WAHA replay) can re-enter and finish the work. Safe to call
  # multiple times — Redis simply ignores DEL on a missing key.
  def release!
    ::Redis::Alfred.delete(@key)
  end
end

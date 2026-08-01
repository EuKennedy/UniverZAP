# Sliding-window counter backed by a Redis sorted set. Each hit is a member
# scored by its epoch timestamp; the "window" is how many hits landed in the
# last N seconds. More accurate than a fixed-bucket counter and, unlike a
# per-call SQL COUNT, keeps hot paths (e.g. the Athenas autopilot reply loop)
# off Postgres.
#
# Concurrency: `record!` is meant to run under an external per-subject lock
# (the autopilot holds the conversation row lock while it records a reply), so a
# plain check-then-record is race-free for a given key. `exceeded?` is a
# non-recording read, safe to call lock-free as an early bail. If strict
# atomicity is ever needed without an outer lock, move prune+count+add into a
# single Lua script.
class Redis::SlidingWindowRateLimiter
  def initialize(key, limit:, window:)
    @key = key
    @limit = limit.to_i
    @window = window.to_i
  end

  # True once the subject has already logged `limit` hits within the window.
  def exceeded?
    count >= @limit
  end

  # Log one hit at "now" and keep the key from outliving the window.
  def record!
    now = Time.now.to_f
    Redis::Alfred.zadd(@key, now, "#{now}:#{SecureRandom.hex(4)}")
    Redis::Alfred.expire(@key, @window + 1)
  end

  # Live count of hits still inside the window (prunes stale members first).
  def count
    prune
    Redis::Alfred.zcard(@key)
  end

  private

  def prune
    cutoff = Time.now.to_f - @window
    Redis::Alfred.zremrangebyscore(@key, 0, cutoff)
  end
end

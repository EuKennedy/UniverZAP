# Resolves the belezaki `external_user_id` for a Univerzap account.
#
# The id is stamped on the account owner during the login bridge
# (`Connect::BridgeController`): on the User's custom_attributes and on the
# UnivercartSubscription. One Univerzap account = one belezaki salon.
#
# The raw resolve runs 2-3 DB queries; since it's called on every autopilot
# reply and the value effectively never changes, it's cached in Redis with a
# short TTL and negative caching (accounts with no salon don't pay the lookup
# each turn). A re-link is visible after at most CACHE_TTL; the cache is
# fail-safe, so a Redis outage just degrades to the uncached path.
class Ai::Belezaki::TenantResolver
  CACHE_TTL = 5.minutes
  # Sentinel so a "no external id" result is cached too (not treated as a miss).
  NO_EXTERNAL_ID = '__none__'.freeze

  def self.external_id(account)
    return nil if account.blank?

    cached = cached_external_id(account.id)
    return (cached == NO_EXTERNAL_ID ? nil : cached) unless cached.nil?

    resolve_external_id(account).tap { |value| cache_external_id(account.id, value) }
  end

  def self.resolve_external_id(account)
    admin_ids = account.account_users
                       .where(role: AccountUser.roles[:administrator])
                       .pluck(:user_id)
    return nil if admin_ids.empty?

    from_subscription(admin_ids) || from_custom_attributes(admin_ids)
  end

  # Deterministic + current salon binding: only an ACTIVE subscription may bind
  # the salon, and when an admin set maps to more than one row (e.g. a
  # belezaki-linked user invited into another linked account) newest wins.
  # Without the order + status filter, `pick` returned an arbitrary heap-order
  # row and the cache then pinned that arbitrary salon for CACHE_TTL — the agent
  # could read availability and book against the WRONG tenant's agenda.
  def self.from_subscription(user_ids)
    UnivercartSubscription.active.where(user_id: user_ids).order(created_at: :desc).pick(:external_user_id).presence
  end

  def self.from_custom_attributes(user_ids)
    User.where(id: user_ids).find_each do |user|
      value = (user.custom_attributes || {})['belezaki_external_user_id']
      return value if value.present?
    end
    nil
  end

  def self.cache_key(account_id)
    format(Redis::RedisKeys::BELEZAKI_EXTERNAL_ID, account_id: account_id)
  end

  def self.cached_external_id(account_id)
    Redis::Alfred.get(cache_key(account_id))
  rescue StandardError => e
    Rails.logger.warn("[Belezaki] external_id cache read failed: #{e.message}")
    nil
  end

  def self.cache_external_id(account_id, value)
    Redis::Alfred.set(cache_key(account_id), value.presence || NO_EXTERNAL_ID, ex: CACHE_TTL.to_i)
  rescue StandardError => e
    Rails.logger.warn("[Belezaki] external_id cache write failed: #{e.message}")
  end
end

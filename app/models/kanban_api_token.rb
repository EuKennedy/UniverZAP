# == Schema Information
#
# Table name: kanban_api_tokens
#
#  id                   :bigint           not null, primary key
#  account_id           :bigint           not null
#  created_by_user_id   :bigint
#  name                 :string           not null
#  token_prefix         :string           not null
#  token_digest         :string           not null
#  scopes               :jsonb            not null, default []
#  expires_at           :datetime
#  last_used_at         :datetime
#  last_used_ip         :string
#  revoked_at           :datetime
#  revoked_by_user_id   :bigint
#
# Indexes
#  index_kanban_api_tokens_on_account_id_and_revoked_at
#  index_kanban_api_tokens_on_token_digest (UNIQUE)
#  index_kanban_api_tokens_on_token_prefix
#
# Tokens follow the GitHub / Stripe pattern: a prefixed, high-entropy
# string that is shown ONCE on creation and stored as a SHA-256 digest
# server-side. The full raw token is unrecoverable — operators rotate
# instead of recovering. This gives us secure-by-default storage even
# if the DB leaks.
#
# Format: `zk_live_<32 chars of base58>` (37 chars total). The prefix
# distinguishes UniverZAP Kanban tokens from any other API key the
# operator pastes, and the `live` segment is reserved for production
# (vs. future `test` tokens).
class KanbanApiToken < ApplicationRecord
  TOKEN_PREFIX = 'zk_live_'.freeze
  TOKEN_ENTROPY_BYTES = 24
  AVAILABLE_SCOPES = %w[
    read:funnels write:funnels
    read:tasks write:tasks
    read:user_tasks write:user_tasks
    read:webhooks write:webhooks
    manage:automations
  ].freeze

  belongs_to :account
  belongs_to :created_by_user, class_name: 'User', optional: true

  validates :name, presence: true, length: { maximum: 120 }
  validates :token_digest, presence: true, uniqueness: true
  validates :token_prefix, presence: true
  validate  :validate_scopes

  scope :active, -> { where(revoked_at: nil).where('expires_at IS NULL OR expires_at > ?', Time.current) }

  attr_accessor :raw_token

  # Generates a fresh token, populates the prefix + digest, and exposes
  # the raw value on `raw_token` for the controller to return ONCE.
  def self.generate!(attrs)
    raw = "#{TOKEN_PREFIX}#{SecureRandom.urlsafe_base64(TOKEN_ENTROPY_BYTES)}"
    token = new(attrs.merge(
                  token_prefix: raw[0, 16],
                  token_digest: digest_for(raw)
                ))
    token.raw_token = raw
    token.save!
    token
  end

  def self.digest_for(raw)
    Digest::SHA256.hexdigest(raw)
  end

  # Constant-time lookup: digest the candidate, find by digest. The
  # query is account-agnostic; the controller then matches the loaded
  # token's `account_id` against the request scope to prevent confused
  # deputy attacks.
  def self.authenticate(raw)
    return nil if raw.blank?
    return nil unless raw.start_with?(TOKEN_PREFIX)

    token = find_by(token_digest: digest_for(raw))
    return nil if token.nil?
    return nil if token.revoked?
    return nil if token.expired?

    token
  end

  def revoked?
    revoked_at.present?
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def includes_scope?(scope)
    scope = scope.to_s
    scopes.map(&:to_s).include?(scope)
  end

  def revoke!(by_user: nil)
    update!(revoked_at: Time.current, revoked_by_user_id: by_user&.id)
  end

  # `update_columns` is intentional — we update the timestamp on EVERY
  # authenticated request (potentially every API call). Going through
  # validations + callbacks here would re-sign tokens, fire AR
  # callbacks, and turn a sub-ms write into ~10ms. Skipping is the
  # correct tradeoff for a write-only counter.
  # rubocop:disable Rails/SkipsModelValidations
  def track_use!(remote_ip: nil)
    update_columns(
      last_used_at: Time.current,
      last_used_ip: remote_ip.to_s.first(64),
      updated_at: Time.current
    )
  end
  # rubocop:enable Rails/SkipsModelValidations

  def push_event_data
    {
      id: id,
      name: name,
      token_prefix: token_prefix,
      scopes: scopes,
      expires_at: expires_at&.to_i,
      last_used_at: last_used_at&.to_i,
      last_used_ip: last_used_ip,
      revoked_at: revoked_at&.to_i,
      created_at: created_at.to_i
    }
  end

  private

  def validate_scopes
    return if scopes.is_a?(Array) && (scopes.map(&:to_s) - AVAILABLE_SCOPES).empty?

    invalid = (Array(scopes).map(&:to_s) - AVAILABLE_SCOPES)
    errors.add(:scopes, "unsupported: #{invalid.join(', ')}")
  end
end

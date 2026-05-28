# == Schema Information
#
# Table name: kanban_webhook_subscriptions
#
#  id                    :bigint           not null, primary key
#  account_id            :bigint           not null
#  created_by_user_id    :bigint
#  name                  :string           not null
#  url                   :string           not null
#  events                :jsonb            not null, default []
#  secret                :string           not null
#  active                :boolean          not null, default true
#  delivery_count        :integer          not null, default 0
#  failure_count         :integer          not null, default 0
#  last_delivered_at     :datetime
#  last_failed_at        :datetime
#  last_error_message    :string
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#
# Each subscription describes an outbound destination for kanban
# events. The kanban entity emitters (task created/moved/completed,
# automation fired, ...) iterate over `KanbanWebhookSubscription.active`
# for the account and enqueue a delivery job per match.
#
# Why a dedicated table instead of reusing Chatwoot's `Webhook` model?
#   - Different lifecycle (kanban-only events, kanban-scoped scopes).
#   - HMAC signing semantics fit n8n / Stripe verification.
#   - Lets us evolve the event catalogue (events column) without
#     polluting the conversation webhook schema.
class KanbanWebhookSubscription < ApplicationRecord
  EVENTS = %w[
    task.created
    task.updated
    task.moved
    task.completed
    task.deleted
    funnel.created
    funnel.updated
    funnel.deleted
    automation.fired
    automation.failed
  ].freeze

  ALLOWED_SCHEMES = %w[http https].freeze

  belongs_to :account
  belongs_to :created_by_user, class_name: 'User', optional: true

  validates :name, presence: true, length: { maximum: 120 }
  validates :url, presence: true, length: { maximum: 2048 }
  validates :secret, presence: true, length: { maximum: 128 }
  validate  :validate_url
  validate  :validate_events

  scope :active, -> { where(active: true) }

  before_validation :assign_default_secret, on: :create

  # Yield active subscriptions on the account that subscribed to this
  # specific event (or to all events when `events` is an empty array).
  def self.for_event(account_id:, event:)
    active
      .where(account_id: account_id)
      .where('events = ?', '[]')
      .or(active.where(account_id: account_id).where('events @> ?', [event].to_json))
  end

  def push_event_data(include_secret: false)
    payload = {
      id: id,
      account_id: account_id,
      name: name,
      url: url,
      events: events,
      active: active,
      delivery_count: delivery_count,
      failure_count: failure_count,
      last_delivered_at: last_delivered_at&.to_i,
      last_failed_at: last_failed_at&.to_i,
      last_error_message: last_error_message,
      created_at: created_at.to_i
    }
    payload[:secret] = secret if include_secret
    payload
  end

  # Counter writes only — going through validations + callbacks here
  # would round-trip the entire payload on every delivery. Skipping is
  # the correct tradeoff for a high-frequency counter.
  # rubocop:disable Rails/SkipsModelValidations
  def track_delivery_success!
    update_columns(
      delivery_count: delivery_count + 1,
      last_delivered_at: Time.current,
      updated_at: Time.current
    )
  end

  def track_delivery_failure!(message)
    update_columns(
      failure_count: failure_count + 1,
      last_failed_at: Time.current,
      last_error_message: message.to_s.truncate(500),
      updated_at: Time.current
    )
  end
  # rubocop:enable Rails/SkipsModelValidations

  private

  def assign_default_secret
    self.secret ||= SecureRandom.hex(32)
  end

  def validate_url
    uri = URI.parse(url.to_s)
    return if ALLOWED_SCHEMES.include?(uri.scheme.to_s.downcase) && uri.host.present?

    errors.add(:url, 'must be a valid http(s) URL')
  rescue URI::InvalidURIError
    errors.add(:url, 'is malformed')
  end

  def validate_events
    return errors.add(:events, 'must be an array') unless events.is_a?(Array)
    return if events.empty?

    invalid = events.map(&:to_s) - EVENTS
    return if invalid.empty?

    errors.add(:events, "unknown: #{invalid.join(', ')}")
  end
end

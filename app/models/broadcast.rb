# == Schema Information
#
# Table name: broadcasts
#
#  id           :bigint           not null, primary key
#  account_id   :bigint           not null
#  inbox_id     :bigint
#  name         :string           not null
#  mode         :string           default("waha"), not null
#  status       :integer          default(0), not null
#  message      :jsonb            default({})
#  audience     :jsonb            default({})
#  throttle     :jsonb            default({})
#  scheduled_at :datetime
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
# A broadcast is a mass WhatsApp dispatch, in one of two modes.
# `waha`     — free text through MessageBuilder, so it renders inside Chatwoot
#              AND dispatches to WhatsApp via the WAHA connector.
# `official` — an approved template through the Meta Cloud API.
class Broadcast < ApplicationRecord
  belongs_to :account
  # Inbox is chosen later in the composer, so a fresh broadcast starts without one.
  belongs_to :inbox, optional: true

  has_many :broadcast_recipients, dependent: :destroy

  # draft     — being composed, never dispatches.
  # scheduled — queued for a future scheduled_at.
  # running   — actively dispatching batches.
  # paused    — halted mid-flight; no new batches.
  # completed — every recipient processed.
  enum status: { draft: 0, scheduled: 1, running: 2, paused: 3, completed: 4 }, _prefix: :status

  MODES = %w[waha official].freeze

  validates :name, presence: true
  validates :mode, inclusion: { in: MODES }
  validate :mode_matches_inbox

  def message_text
    message['text']
  end

  def audience_filters
    audience || {}
  end

  def batch_min
    throttle_value('batch_min', 3)
  end

  def batch_max
    throttle_value('batch_max', 8)
  end

  def delay_min
    throttle_value('delay_min', 20)
  end

  def delay_max
    throttle_value('delay_max', 60)
  end

  def daily_cap
    throttle_value('daily_cap', 500)
  end

  private

  # The modes speak different protocols: `official` ships an approved template
  # through the Cloud API, `waha` ships free text. Crossing them fails silently
  # — free text on a Cloud inbox is refused outside the 24h window, and the
  # recipient was marked sent anyway.
  def mode_matches_inbox
    return if inbox.blank?
    # Only judge the pair when somebody actually sets it. Rows that predate this
    # rule would otherwise fail on status_completed! and leave the broadcast
    # stuck in `running` after every recipient was already sent.
    return unless mode_changed? || inbox_id_changed?

    errors.add(:mode, 'official requires a WhatsApp Cloud inbox') if mode == 'official' && !cloud_inbox?
    errors.add(:mode, 'waha cannot send free text on a WhatsApp Cloud inbox') if mode == 'waha' && cloud_inbox?
  end

  def cloud_inbox?
    channel = inbox.channel
    channel.is_a?(Channel::Whatsapp) && channel.provider == 'whatsapp_cloud'
  end

  def throttle_value(key, fallback)
    value = (throttle || {})[key]
    value.presence ? value.to_i : fallback
  end
end

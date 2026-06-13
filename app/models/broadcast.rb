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
# A broadcast is a mass WhatsApp dispatch. Phase 1 ships WAHA send mode only:
# each recipient gets an outgoing message created through MessageBuilder so it
# renders inside Chatwoot AND dispatches to WhatsApp via the WAHA connector.
class Broadcast < ApplicationRecord
  belongs_to :account
  belongs_to :inbox

  has_many :broadcast_recipients, dependent: :destroy

  # draft     — being composed, never dispatches.
  # scheduled — queued for a future scheduled_at.
  # running   — actively dispatching batches.
  # paused    — halted mid-flight; no new batches.
  # completed — every recipient processed.
  enum status: { draft: 0, scheduled: 1, running: 2, paused: 3, completed: 4 }, _prefix: :status

  validates :name, presence: true

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

  def throttle_value(key, fallback)
    value = (throttle || {})[key]
    value.presence ? value.to_i : fallback
  end
end

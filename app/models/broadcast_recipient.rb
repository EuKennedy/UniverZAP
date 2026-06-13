# == Schema Information
#
# Table name: broadcast_recipients
#
#  id              :bigint           not null, primary key
#  broadcast_id    :bigint           not null
#  contact_id      :bigint           not null
#  conversation_id :bigint
#  status          :integer          default(0), not null
#  error           :string
#  sent_at         :datetime
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
class BroadcastRecipient < ApplicationRecord
  belongs_to :broadcast
  belongs_to :contact

  # pending   — not yet dispatched.
  # sent      — handed off to the WAHA connector.
  # delivered — provider confirmed delivery.
  # read      — recipient opened it.
  # failed    — dispatch raised; see `error`.
  enum status: { pending: 0, sent: 1, delivered: 2, read: 3, failed: 4 }, _prefix: :status
end

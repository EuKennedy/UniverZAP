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
#  message_id      :bigint
#  replied_at      :datetime
#  send_after      :datetime
#  skip_reason     :string
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
  # skipped   — never sent on purpose; see `skip_reason` (opted_out,
  #             recent_activity, no_phone). Not a failure: it is the guard working.
  enum status: { pending: 0, sent: 1, delivered: 2, read: 3, failed: 4, skipped: 5 }, _prefix: :status

  belongs_to :message, optional: true

  # Pending recipients whose turn has come (smart timing pushes some forward).
  scope :ready, -> { status_pending.where(send_after: nil).or(status_pending.where(send_after: ..Time.current)) }
end

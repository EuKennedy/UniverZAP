# One belezaki salon bound to ONE agent.
#
# Per agent and not per account, like the Google grant next to it: the same
# operator may run a salon and a clinic as two agents, and one agenda must never
# answer for the other.
#
# The salon id is frozen here instead of being resolved on every reply. The
# resolution goes through the account and is cached, and a cached arbitrary row
# is exactly how an agent once ended up reading availability from the WRONG
# tenant's agenda.
class Ai::Belezaki::Connection < ApplicationRecord
  self.table_name = 'ai_belezaki_connections'

  STATUSES = %w[active revoked].freeze

  belongs_to :ai_assistant, class_name: 'Ai::Assistant'
  belongs_to :account

  validates :external_id, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :ai_assistant_id, uniqueness: true

  scope :active, -> { where(status: 'active') }

  def active?
    status == 'active'
  end

  # Recorded rather than raised: the agent has to stop offering times, and
  # somebody has to be told why, but the customer must never read a stack trace.
  def revoke!(reason)
    update!(status: 'revoked', last_error: reason.to_s.truncate(300), last_error_at: Time.current)
  end

  def push_event_data
    { id: id, salon_name: salon_name, timezone: timezone, status: status, connected_at: connected_at }
  end
end

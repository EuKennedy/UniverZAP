# One OAuth grant to a Google account, belonging to ONE agent.
#
# Per agent rather than per account because an operator may run three agents
# that are three different businesses, each with its own calendar. Sharing the
# grant would couple agendas that have nothing to do with each other.
class Ai::Calendar::Connection < ApplicationRecord
  self.table_name = 'ai_calendar_connections'

  STATUSES = %w[active revoked].freeze

  # Only the refresh token is stored. Access tokens expire in an hour, so
  # keeping one would mean keeping something already stale.
  encrypts :encrypted_refresh_token, deterministic: false if Chatwoot.encryption_configured?

  belongs_to :ai_assistant, class_name: 'Ai::Assistant'
  belongs_to :account

  has_many :professionals, class_name: 'Ai::Calendar::Professional',
                           foreign_key: :ai_calendar_connection_id, dependent: :destroy, inverse_of: :connection

  validates :google_email, presence: true
  validates :encrypted_refresh_token, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: 'active') }

  def revoked?
    status == 'revoked'
  end

  # Google answered that the grant is gone. Recorded rather than raised: the
  # agent has to stop scheduling, and somebody has to be told why, but the
  # customer must never read a stack trace.
  def revoke!(reason)
    update!(status: 'revoked', last_error: reason.to_s.truncate(300), last_error_at: Time.current)
  end

  def push_event_data
    { id: id, google_email: google_email, status: status, professionals: professionals.map(&:push_event_data) }
  end
end

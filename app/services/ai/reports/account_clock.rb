# The local clock of the business, for a panel that reports hours.
#
# `Time.zone` is UTC on this installation, so reading an hour out of it puts a
# Brazilian salon's busiest moment three hours from where it happened. Every
# number in the panel that mentions a time of day is wrong by that much unless
# somebody decides what "local" means, and the honest answer is: whatever the
# operator already told us.
#
# In order of how much we trust it:
#   1. The agenda's timezone. Typed by hand in "Configurar negócio" by the
#      person who runs the place, and the agent books real appointments against
#      it, so a wrong value there would already be visible. The belezaki
#      connection carries the same statement for a salon whose book lives there.
#   2. An inbox timezone that is not the default. Chatwoot ships 'UTC' on every
#      inbox, so only a value somebody changed counts as a statement.
#   3. Time.zone, which is the installation's own answer and the only one left.
#
# Whatever is picked travels in the payload, so the chart can say which clock it
# is drawn on instead of leaving the operator to assume it is theirs.
class Ai::Reports::AccountClock
  DEFAULT_INBOX_TIMEZONE = 'UTC'.freeze

  def initialize(account)
    @account = account
  end

  # An ActiveSupport::TimeZone, always. An unknown name in the database must not
  # take the report down, so anything TZInfo refuses falls through to the next
  # source rather than raising.
  def zone
    @zone ||= resolve(agenda_timezone) || resolve(belezaki_timezone) || resolve(inbox_timezone) || Time.zone
  end

  # The IANA name, which is what Postgres understands in AT TIME ZONE.
  def tz_name
    zone.tzinfo.name
  end

  private

  def resolve(name)
    return nil if name.blank?

    ActiveSupport::TimeZone[name]
  end

  def agenda_timezone
    Ai::Calendar::Professional.where(account_id: @account.id, active: true)
                              .order(:id).pick(:timezone)
  end

  def belezaki_timezone
    Ai::Belezaki::Connection.where(account_id: @account.id, status: 'active').order(:id).pick(:timezone)
  end

  def inbox_timezone
    @account.inboxes.where.not(timezone: [nil, '', DEFAULT_INBOX_TIMEZONE]).order(:id).pick(:timezone)
  end
end

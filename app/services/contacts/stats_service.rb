# The figures at the top of the contacts page. Same base as the list, so the
# total here is the total the pagination shows.
class Contacts::StatsService
  RECENT_WINDOW = 30.days

  def initialize(account)
    @account = account
  end

  def perform
    contacts = @account.contacts.resolved_contacts(use_crm_v2: @account.feature_enabled?('crm_v2'))
    {
      total: contacts.count,
      recent: contacts.where(created_at: RECENT_WINDOW.ago..).count,
      recurring: contacts.where("contacts.custom_attributes ->> 'recorrente' = 'true'").count,
      without_phone: contacts.where(phone_number: nil).count
    }
  end
end

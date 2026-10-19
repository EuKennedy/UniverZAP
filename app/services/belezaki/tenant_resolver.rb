# Which belezaki salon an account is.
#
# Two ways to know: the belezaki app connected in Apps (the admin typed the
# salon id, and the connect probe confirmed it), or — for accounts born through
# the login bridge — the id the bridge stamped on the owner, which is what
# Ai::Belezaki::TenantResolver reads. Apps wins because it is the one the
# operator can see and change.
class Belezaki::TenantResolver
  APP_ID = 'belezaki'.freeze

  def self.hook(account)
    account.hooks.enabled.find_by(app_id: APP_ID)
  end

  def self.external_id(account)
    hook(account)&.settings&.dig('external_id').presence || Ai::Belezaki::TenantResolver.external_id(account)
  end
end

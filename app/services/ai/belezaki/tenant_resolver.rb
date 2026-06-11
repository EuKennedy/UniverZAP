# Resolves the belezaki `external_user_id` for a Univerzap account.
#
# The id is stamped on the account owner during the login bridge
# (`Connect::BridgeController`): on the User's custom_attributes and on the
# UnivercartSubscription. One Univerzap account = one belezaki salon.
class Ai::Belezaki::TenantResolver
  def self.external_id(account)
    return nil if account.blank?

    admin_ids = account.account_users
                       .where(role: AccountUser.roles[:administrator])
                       .pluck(:user_id)
    return nil if admin_ids.empty?

    from_subscription(admin_ids) || from_custom_attributes(admin_ids)
  end

  def self.from_subscription(user_ids)
    UnivercartSubscription.where(user_id: user_ids).pick(:external_user_id).presence
  end

  def self.from_custom_attributes(user_ids)
    User.where(id: user_ids).find_each do |user|
      value = (user.custom_attributes || {})['belezaki_external_user_id']
      return value if value.present?
    end
    nil
  end
end

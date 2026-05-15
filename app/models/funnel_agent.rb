# == Schema Information
#
# Table name: funnel_agents
#
#  id         :bigint           not null, primary key
#  funnel_id  :bigint           not null
#  user_id    :bigint           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class FunnelAgent < ApplicationRecord
  belongs_to :funnel
  belongs_to :user

  validates :user_id, uniqueness: { scope: :funnel_id }
  validate  :user_belongs_to_funnel_account

  private

  def user_belongs_to_funnel_account
    return if funnel.blank? || user.blank?
    return if user.accounts.exists?(id: funnel.account_id)

    errors.add(:user, 'must belong to the funnel account')
  end
end

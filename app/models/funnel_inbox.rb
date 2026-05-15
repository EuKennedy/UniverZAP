# == Schema Information
#
# Table name: funnel_inboxes
#
#  id         :bigint           not null, primary key
#  funnel_id  :bigint           not null
#  inbox_id   :bigint           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class FunnelInbox < ApplicationRecord
  belongs_to :funnel
  belongs_to :inbox

  validates :inbox_id, uniqueness: { scope: :funnel_id }
  validate  :inbox_belongs_to_funnel_account

  private

  def inbox_belongs_to_funnel_account
    return if funnel.blank? || inbox.blank?
    return if funnel.account_id == inbox.account_id

    errors.add(:inbox, 'must belong to the funnel account')
  end
end

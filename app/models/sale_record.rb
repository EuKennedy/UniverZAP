# == Schema Information
#
# Table name: sale_records
#
#  id          :bigint           not null, primary key
#  account_id  :bigint           not null
#  contact_id  :bigint           not null
#  user_id     :bigint           not null
#  amount      :decimal(12, 2)   default(0.0), not null
#  recorded_at :datetime         not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# A sale_record is a single sale value an agent (user) registers against a
# contact. Each record feeds the agent's SalesGoal progress AND accumulates
# onto the contact's "Valor em compras" running total.
class SaleRecord < ApplicationRecord
  belongs_to :account
  belongs_to :contact
  belongs_to :user

  after_create :bump_contact_total

  private

  # Add this sale's amount to the contact's cumulative purchase total stored in
  # additional_attributes['valor_em_compras'].
  def bump_contact_total
    total = contact.additional_attributes['valor_em_compras'].to_f + amount.to_f
    contact.additional_attributes['valor_em_compras'] = total
    contact.save!
  end
end

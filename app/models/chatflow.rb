# == Schema Information
#
# Table name: chatflows
#
#  id             :bigint           not null, primary key
#  account_id     :bigint           not null
#  inbox_id       :bigint
#  name           :string           not null
#  description    :text
#  status         :integer          default(0), not null
#  trigger_type   :integer          default(0), not null
#  trigger_config :jsonb            default({}), not null
#  start_node_id  :bigint
#  display_id     :bigint
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
class Chatflow < ApplicationRecord
  include AccountDisplayId

  belongs_to :account
  belongs_to :inbox, optional: true

  has_many :nodes, class_name: 'ChatflowNode', dependent: :destroy, inverse_of: :chatflow
  has_many :edges, class_name: 'ChatflowEdge', dependent: :destroy, inverse_of: :chatflow
  has_many :executions, class_name: 'ChatflowExecution', dependent: :destroy, inverse_of: :chatflow

  belongs_to :start_node, class_name: 'ChatflowNode', optional: true

  # draft  — being edited, never fires.
  # active — live; inbound messages can trigger/advance it.
  # archived — retired, kept for history.
  enum status: { draft: 0, active: 1, archived: 2 }, _prefix: :status

  # on_first_message — fires once, on the first inbound message of a conversation.
  # keyword          — fires when an inbound message matches trigger_config['keywords'].
  # any_message      — fires on every inbound message with no live execution.
  enum trigger_type: { on_first_message: 0, keyword: 1, any_message: 2 }, _prefix: :trigger

  validates :name, presence: true, length: { maximum: 255 }
  validates :description, length: { maximum: 5000 }, allow_blank: true
  validate :inbox_belongs_to_account

  scope :live, -> { status_active }

  def keywords
    Array(trigger_config['keywords']).map { |k| k.to_s.downcase.strip }.reject(&:blank?)
  end

  # Digits-only tester number used to gate a flow that is in test mode.
  def test_digits
    test_phone.to_s.gsub(/\D/, '')
  end

  private

  def inbox_belongs_to_account
    return if inbox.blank? || account.blank?
    return if inbox.account_id == account_id

    errors.add(:inbox, 'must belong to the same account')
  end
end

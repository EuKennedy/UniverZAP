# == Schema Information
#
# Table name: chatflows
#
#  id             :bigint           not null, primary key
#  color          :string           default("#5FB89F"), not null
#  description    :text
#  name           :string(255)      not null
#  status         :integer          default("draft"), not null
#  test_mode      :boolean          default(FALSE), not null
#  test_phone     :string
#  trigger_config :jsonb            not null
#  trigger_type   :integer          default("on_first_message"), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#  display_id     :bigint
#  inbox_id       :bigint
#  start_node_id  :bigint
#
# Indexes
#
#  index_chatflows_on_account_id                 (account_id)
#  index_chatflows_on_account_id_and_display_id  (account_id,display_id) UNIQUE WHERE (display_id IS NOT NULL)
#  index_chatflows_on_account_id_and_status      (account_id,status)
#  index_chatflows_on_inbox_id                   (inbox_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (inbox_id => inboxes.id) ON DELETE => cascade
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
  # ad_referral      — fires when an inbound message came from a Click-to-WhatsApp ad.
  # no_reply         — started by the waiting scanner when the customer has waited
  #                    trigger_config['no_reply_minutes'] without a human reply.
  enum trigger_type: { on_first_message: 0, keyword: 1, any_message: 2, webhook: 3, ad_referral: 4, no_reply: 5 }, _prefix: :trigger

  validates :name, presence: true, length: { maximum: 255 }
  validates :description, length: { maximum: 5000 }, allow_blank: true
  validate :inbox_belongs_to_account

  scope :live, -> { status_active }

  # O nome que assina as mensagens deste fluxo.
  #
  # O Chatwoot assina mensagem com o nome de QUEM escreveu, e uma mensagem de
  # fluxo não tem autor humano — a assinatura saía vazia e o cliente recebia os
  # asteriscos do negrito sem nada no meio. Em branco aqui, o fluxo não assina:
  # melhor sem nome do que com um nome inventado por nós.
  def sender_name
    trigger_config['sender_name'].to_s.strip
  end

  def no_reply_minutes
    minutes = trigger_config['no_reply_minutes'].to_i
    minutes.positive? ? minutes : 15
  end

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

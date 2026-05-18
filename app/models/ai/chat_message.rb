# == Schema Information
#
# Table name: ai_chat_messages
#
class Ai::ChatMessage < ApplicationRecord
  self.table_name = 'ai_chat_messages'

  ROLES = %w[user assistant].freeze
  CONTENT_LIMIT = 32_000

  belongs_to :chat_thread, class_name: 'Ai::ChatThread', foreign_key: :ai_chat_thread_id, inverse_of: :chat_messages
  belongs_to :account

  validates :role, presence: true, inclusion: { in: ROLES }
  validates :content, presence: true, length: { maximum: CONTENT_LIMIT }

  before_validation :ensure_account

  def push_event_data
    {
      id: id,
      role: role,
      content: content,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      cost_usd: cost_usd,
      model: model,
      created_at: created_at.to_i
    }
  end

  private

  def ensure_account
    self.account_id ||= chat_thread&.account_id
  end
end

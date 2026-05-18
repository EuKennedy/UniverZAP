# == Schema Information
#
# Table name: ai_chat_threads
#
class Ai::ChatThread < ApplicationRecord
  self.table_name = 'ai_chat_threads'

  TITLE_LIMIT = 180
  RECENT_MESSAGE_WINDOW = 20

  belongs_to :account
  belongs_to :user
  belongs_to :ai_assistant, class_name: 'Ai::Assistant'
  belongs_to :conversation, optional: true
  has_many :chat_messages,
           -> { order(created_at: :asc) },
           class_name: 'Ai::ChatMessage',
           foreign_key: :ai_chat_thread_id,
           inverse_of: :chat_thread,
           dependent: :destroy

  validates :title, presence: true, length: { maximum: TITLE_LIMIT }
  validates :last_activity_at, presence: true

  before_validation :ensure_last_activity_at

  scope :active, -> { where(archived_at: nil) }
  scope :for_user, ->(user) { where(user_id: user.id) }
  scope :for_conversation, ->(conversation_id) { where(conversation_id: conversation_id) }
  scope :recent, -> { order(last_activity_at: :desc) }

  def recent_messages_for_llm
    chat_messages.order(created_at: :desc).limit(RECENT_MESSAGE_WINDOW).reverse
  end

  def archive!
    update!(archived_at: Time.current)
  end

  def touch_activity!
    touch(:last_activity_at)
  end

  def push_event_data
    {
      id: id,
      title: title,
      conversation_id: conversation_id,
      ai_assistant_id: ai_assistant_id,
      last_activity_at: last_activity_at.to_i,
      archived_at: archived_at&.to_i,
      created_at: created_at.to_i
    }
  end

  private

  def ensure_last_activity_at
    self.last_activity_at ||= Time.current
  end
end

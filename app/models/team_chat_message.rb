# == Schema Information
#
# Table name: team_chat_messages
#
#  id         :bigint           not null, primary key
#  channel_id :bigint           not null
#  user_id    :bigint           not null
#  content    :text             not null
#  edited_at  :datetime
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes:
#   index_team_chat_messages_on_channel_id_and_created_at
#
class TeamChatMessage < ApplicationRecord
  MAX_LENGTH = 8000

  belongs_to :channel, class_name: 'TeamChatChannel'
  belongs_to :user

  validates :content, presence: true, length: { maximum: MAX_LENGTH }

  after_create_commit  :broadcast_created
  after_update_commit  :broadcast_updated
  after_destroy_commit :broadcast_destroyed

  scope :chronological, -> { order(:created_at, :id) }

  # `account_id` is reached through the channel — the broadcaster needs it
  # to scope the stream and we don't denormalize it onto the message row.
  delegate :account_id, to: :channel

  def push_event_data
    {
      id: id,
      channel_id: channel_id,
      content: content,
      edited: edited_at.present?,
      edited_at: edited_at&.to_i,
      user: { id: user.id, name: user.name, avatar_url: user.avatar_url },
      created_at: created_at.to_i,
      updated_at: updated_at.to_i
    }
  end

  private

  def broadcast_created
    TeamChat::Broadcaster.broadcast('team_chat.message_created', account_id, push_event_data)
  end

  def broadcast_updated
    TeamChat::Broadcaster.broadcast('team_chat.message_updated', account_id, push_event_data)
  end

  def broadcast_destroyed
    TeamChat::Broadcaster.broadcast(
      'team_chat.message_deleted', account_id,
      { id: id, channel_id: channel_id }
    )
  end
end

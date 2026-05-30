# == Schema Information
#
# Table name: team_chat_channels
#
#  id                 :bigint           not null, primary key
#  account_id         :bigint           not null
#  created_by_user_id :bigint
#  name               :string(80)       not null
#  slug               :string(80)       not null
#  description        :text
#  kind               :integer          not null, default 0
#  position           :integer          not null, default 0
#  archived_at        :datetime
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
# Indexes:
#   index_team_chat_channels_on_account_id_and_slug      (unique)
#   index_team_chat_channels_on_account_id_and_position
#
class TeamChatChannel < ApplicationRecord
  # The four channels every account starts with. Seeded lazily by the
  # controller on first index so existing tenants get them without a
  # backfill migration. Order here is the order they render in.
  DEFAULT_CHANNELS = [
    { slug: 'geral', name: 'Geral', description: 'Conversa geral do time.' },
    { slug: 'discussoes', name: 'Discussões', description: 'Debates e ideias.' },
    { slug: 'metas', name: 'Metas', description: 'Objetivos e acompanhamento.' },
    { slug: 'comunicados', name: 'Comunicados Importantes', description: 'Avisos oficiais.' }
  ].freeze

  belongs_to :account
  belongs_to :created_by_user, class_name: 'User', optional: true

  # `t.references :channel` named the FK column `channel_id`, but the
  # default has_many inference derives it from the OWNER class name
  # (`team_chat_channel_id`). Pin the real column + inverse so
  # `channel.messages` and the message's `belongs_to :channel` agree.
  has_many :messages, class_name: 'TeamChatMessage', foreign_key: :channel_id,
                      dependent: :destroy, inverse_of: :channel

  enum kind: { default: 0, custom: 1 }, _prefix: :kind

  validates :name, presence: true, length: { maximum: 80 }
  validates :slug, presence: true, length: { maximum: 80 },
                   uniqueness: { scope: :account_id },
                   format: { with: /\A[a-z0-9][a-z0-9-]*\z/, message: :invalid_slug }

  before_validation :assign_slug, on: :create
  before_validation :assign_position, on: :create

  after_create_commit  :broadcast_created
  after_update_commit  :broadcast_updated
  after_destroy_commit :broadcast_destroyed

  scope :active, -> { where(archived_at: nil) }
  scope :ordered, -> { order(:position, :id) }

  def push_event_data
    {
      id: id,
      account_id: account_id,
      name: name,
      slug: slug,
      description: description,
      kind: kind,
      position: position,
      archived: archived_at.present?,
      message_count: messages.count,
      created_at: created_at.to_i,
      updated_at: updated_at.to_i
    }
  end

  private

  # Derive a URL-safe handle from the name when the client didn't send one.
  # Collisions are caught by the uniqueness validator; the controller maps
  # that to a friendly 422 so the operator can rename.
  def assign_slug
    return if slug.present?

    base = name.to_s.parameterize.presence || 'canal'
    self.slug = base.first(80)
  end

  def assign_position
    return if position.present? && position.positive?

    self.position = (account.team_chat_channels.maximum(:position) || 0) + 1
  end

  def broadcast_created
    TeamChat::Broadcaster.broadcast('team_chat.channel_created', account_id, push_event_data)
  end

  def broadcast_updated
    TeamChat::Broadcaster.broadcast('team_chat.channel_updated', account_id, push_event_data)
  end

  def broadcast_destroyed
    TeamChat::Broadcaster.broadcast('team_chat.channel_deleted', account_id, { id: id })
  end
end

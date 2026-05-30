# == Schema Information
#
# Table name: funnel_stages
#
#  id          :bigint           not null, primary key
#  funnel_id   :bigint           not null
#  name        :string           not null
#  description :text
#  color       :string           default("#64748B"), not null
#  position    :integer          default(0), not null
#  status_type :integer          default(0), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
class FunnelStage < ApplicationRecord
  include KanbanRealtime

  HEX_COLOR_REGEX = /\A#(?:[0-9a-fA-F]{3}){1,2}\z/

  belongs_to :funnel, inverse_of: :funnel_stages
  has_many :kanban_tasks, dependent: :restrict_with_error

  enum status_type: { active: 0, won: 1, lost: 2 }

  validates :name, presence: true, length: { maximum: 120 }
  validates :description, length: { maximum: 2000 }, allow_blank: true
  validates :color, format: { with: HEX_COLOR_REGEX, message: :invalid_hex_color }
  validates :wip_limit, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  before_validation :assign_position, on: :create
  # A kanban without stages is undefined — there'd be nowhere to put
  # tasks, no UI to render, no meaningful "delete" semantics for the
  # board. We surface a friendly error instead of letting the operator
  # destroy the last column and stare at a void. The guard is skipped
  # when the parent funnel itself is going away so cascade teardown
  # still works.
  before_destroy :ensure_not_last_stage

  scope :ordered, -> { order(:position, :id) }

  delegate :account, to: :funnel

  def push_event_data
    {
      id: id,
      funnel_id: funnel_id,
      name: name,
      description: description,
      color: color,
      position: position,
      status_type: status_type,
      wip_limit: wip_limit,
      tasks_count: kanban_tasks.count,
      created_at: created_at.to_i,
      updated_at: updated_at.to_i
    }
  end

  private

  def kanban_event_payload
    push_event_data
  end

  def kanban_destroyed_payload
    { id: id, funnel_id: funnel_id }
  end

  def assign_position
    return if position.present? && position.positive?

    self.position = (funnel&.funnel_stages&.maximum(:position) || 0) + 1
  end

  def ensure_not_last_stage
    # Skip when the parent funnel is going away — its cascade legitimately
    # tears every stage down, including the last one. `cascading_destroy`
    # is set by Funnel#flag_cascade_destroy (prepended before_destroy);
    # `destroyed?`/`marked_for_destruction?` are NOT reliable here because
    # the parent row is deleted only after its dependents.
    return if funnel.nil? || funnel.cascading_destroy ||
              funnel.destroyed? || funnel.marked_for_destruction?
    return if funnel.funnel_stages.where.not(id: id).exists?

    errors.add(:base, I18n.t('errors.funnel_stage.last_stage_protected',
                             default: 'Funis precisam de pelo menos uma etapa. Crie outra antes de remover esta.'))
    throw :abort
  end
end

# == Schema Information
#
# Table name: kanban_tasks
#
#  id              :bigint           not null, primary key
#  account_id      :bigint           not null
#  funnel_id       :bigint           not null
#  funnel_stage_id :bigint           not null
#  title           :string           not null
#  description     :text
#  priority        :integer          default(0), not null
#  position        :integer          default(0), not null
#  start_date      :datetime
#  due_date        :datetime
#  display_id      :bigint
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
class KanbanTask < ApplicationRecord
  belongs_to :account
  belongs_to :funnel
  belongs_to :funnel_stage

  has_many :kanban_task_assignees, dependent: :destroy
  has_many :assignees, through: :kanban_task_assignees, source: :user

  has_many :kanban_task_labels, dependent: :destroy
  has_many :task_labels, through: :kanban_task_labels, source: :label

  has_many :kanban_task_conversations, dependent: :destroy
  has_many :conversations, through: :kanban_task_conversations

  has_many :kanban_task_contacts, dependent: :destroy
  has_many :contacts, through: :kanban_task_contacts

  enum priority: { none: 0, low: 1, medium: 2, high: 3, urgent: 4 }

  validates :title, presence: true, length: { maximum: 255 }
  validates :description, length: { maximum: 5000 }, allow_blank: true
  validate  :funnel_stage_belongs_to_funnel
  validate  :funnel_belongs_to_account

  before_validation :assign_position, on: :create
  before_create     :assign_display_id

  scope :ordered_in_stage, -> { order(:position, :id) }
  scope :for_stage, ->(stage_id) { where(funnel_stage_id: stage_id) }

  def stage_status
    funnel_stage&.status_type
  end

  private

  def assign_position
    return if position.present? && position.positive?

    self.position = (funnel_stage&.kanban_tasks&.maximum(:position) || 0) + 1
  end

  def assign_display_id
    self.display_id ||= (account.kanban_tasks.maximum(:display_id) || 0) + 1
  end

  def funnel_stage_belongs_to_funnel
    return if funnel_stage.blank? || funnel.blank?
    return if funnel_stage.funnel_id == funnel_id

    errors.add(:funnel_stage, 'must belong to the assigned funnel')
  end

  def funnel_belongs_to_account
    return if funnel.blank? || account.blank?
    return if funnel.account_id == account_id

    errors.add(:funnel, 'must belong to the same account')
  end
end

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
  include KanbanRealtime

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

  has_many :custom_values,
           class_name: 'KanbanTaskCustomValue',
           dependent: :destroy,
           inverse_of: :kanban_task

  has_many :time_entries,
           -> { order(started_at: :desc) },
           class_name: 'KanbanTaskTimeEntry',
           dependent: :destroy,
           inverse_of: :kanban_task

  has_many :activities,
           -> { order(created_at: :desc) },
           class_name: 'KanbanTaskActivity',
           dependent: :destroy,
           inverse_of: :kanban_task

  # Self-referential subtask hierarchy. Root cards live in stages; subtasks
  # carry a parent_task_id and are rendered inside the parent's drawer.
  belongs_to :parent_task, class_name: 'KanbanTask', optional: true,
                           inverse_of: :subtasks
  has_many :subtasks,
           -> { order(:position, :id) },
           class_name: 'KanbanTask',
           foreign_key: :parent_task_id,
           dependent: :destroy,
           inverse_of: :parent_task

  enum priority: { none: 0, low: 1, medium: 2, high: 3, urgent: 4 }, _prefix: :priority

  scope :root_tasks, -> { where(parent_task_id: nil) }

  validates :title, presence: true, length: { maximum: 255 }
  validates :description, length: { maximum: 5000 }, allow_blank: true
  validate  :funnel_stage_belongs_to_funnel
  validate  :funnel_belongs_to_account

  before_validation :assign_position, on: :create
  before_create     :assign_display_id

  after_create_commit  :run_automation_on_create
  after_update_commit  :run_automation_on_stage_change

  scope :ordered_in_stage, -> { order(:position, :id) }
  scope :for_stage, ->(stage_id) { where(funnel_stage_id: stage_id) }

  def stage_status
    funnel_stage&.status_type
  end

  def push_event_data
    attributes_payload.merge(associations_payload).merge(timestamps_payload)
  end

  private

  def attributes_payload
    {
      id: id,
      display_id: display_id,
      account_id: account_id,
      funnel_id: funnel_id,
      funnel_stage_id: funnel_stage_id,
      parent_task_id: parent_task_id,
      title: title,
      description: description,
      priority: priority,
      position: position,
      estimate_minutes: estimate_minutes,
      completed_at: completed_at&.to_i,
      start_date: start_date&.to_i,
      due_date: due_date&.to_i
    }
  end

  def associations_payload
    relations_payload.merge(subtasks_payload).merge(custom_values_payload)
  end

  def custom_values_payload
    {
      custom_values: custom_values.map(&:push_event_data),
      total_tracked_seconds: time_entries.where.not(ended_at: nil).sum(:duration_seconds),
      active_time_entry: time_entries.find_by(ended_at: nil)&.push_event_data
    }
  end

  def relations_payload
    {
      assignees: assignees.map { |u| assignee_payload(u) },
      labels: task_labels.map { |l| label_payload(l) },
      conversations: conversations.map { |c| conversation_payload(c) },
      contacts: contacts.map { |c| contact_payload(c) }
    }
  end

  def subtasks_payload
    loaded = subtasks.to_a
    {
      subtasks: loaded.map { |s| subtask_payload(s) },
      subtasks_count: loaded.size,
      subtasks_completed_count: loaded.count { |s| s.completed_at.present? }
    }
  end

  def assignee_payload(user)
    { id: user.id, name: user.name, avatar_url: user.avatar_url }
  end

  def label_payload(label)
    { id: label.id, title: label.title, color: label.color }
  end

  def conversation_payload(conversation)
    {
      id: conversation.id,
      display_id: conversation.display_id,
      status: conversation.status,
      inbox_id: conversation.inbox_id,
      inbox_name: conversation.inbox&.name,
      last_activity_at: conversation.last_activity_at&.to_i
    }
  end

  def contact_payload(contact)
    {
      id: contact.id,
      name: contact.name,
      email: contact.email,
      phone_number: contact.phone_number,
      thumbnail: contact.avatar_url
    }
  end

  def subtask_payload(subtask)
    {
      id: subtask.id,
      title: subtask.title,
      position: subtask.position,
      completed_at: subtask.completed_at&.to_i
    }
  end

  def timestamps_payload
    { created_at: created_at.to_i, updated_at: updated_at.to_i }
  end

  def kanban_event_payload
    push_event_data
  end

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

  def run_automation_on_create
    Kanban::AutomationService.handle_task_created(self)
  end

  def run_automation_on_stage_change
    return unless previous_changes.key?('funnel_stage_id')

    Kanban::AutomationService.handle_task_stage_changed(self)
  end
end

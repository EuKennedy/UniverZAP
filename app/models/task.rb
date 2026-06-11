# == Schema Information
#
# Table name: tasks
#
#  id                  :bigint           not null, primary key
#  account_id          :bigint           not null
#  created_by_user_id  :bigint
#  display_id          :bigint
#  title               :string           not null
#  description         :jsonb            not null, default {}
#  status              :integer          not null, default 0
#  urgency             :integer          not null, default 0
#  due_date            :datetime
#  completed_at        :datetime
#  notify_assignees    :boolean          not null, default true
#  custom_attributes   :jsonb            not null, default {}
#  position            :integer          not null, default 0
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
# Indexes:
#   index_tasks_on_account_id_and_status
#   index_tasks_on_account_id_and_due_date
#   index_tasks_on_account_id_and_urgency
#   index_tasks_on_display_id
#
class Task < ApplicationRecord
  include AccountDisplayId

  belongs_to :account
  belongs_to :created_by_user, class_name: 'User', optional: false
  # Recurrence parent: when a task is spawned by `RecurrenceGenerator`,
  # we point back at the template row so the dashboard can group the
  # series and the scheduler knows where to advance `next_occurrence_at`.
  belongs_to :recurrence_parent, class_name: 'Task', optional: true

  has_many :task_assignees, dependent: :destroy
  has_many :assignees, through: :task_assignees, source: :user
  has_many :task_comments, dependent: :destroy
  has_many :task_activities, dependent: :destroy
  has_many :recurrence_children, class_name: 'Task', foreign_key: :recurrence_parent_id, dependent: :nullify,
                                 inverse_of: :recurrence_parent

  enum status: { open: 0, in_progress: 1, blocked: 2, done: 3, cancelled: 4 }, _prefix: :status
  enum urgency: { none: 0, low: 1, medium: 2, high: 3, urgent: 4 }, _prefix: :urgency

  validates :title, presence: true, length: { maximum: 255 }

  scope :active, -> { where(status: %i[open in_progress]) }
  scope :overdue, lambda {
    where.not(due_date: nil)
         .where('due_date < ?', Time.current)
         .where.not(status: %i[done cancelled])
  }
  scope :assigned_to, lambda { |user_id|
    joins(:task_assignees).where(task_assignees: { user_id: user_id }).distinct
  }
  scope :created_by, ->(user_id) { where(created_by_user_id: user_id) }
  scope :recurring, -> { where.not(recurrence_rule: {}) }
  scope :due_for_recurrence, lambda {
    recurring.where.not(next_occurrence_at: nil).where('next_occurrence_at <= ?', Time.current)
  }

  after_create_commit  :log_creation_activity
  after_create_commit  :broadcast_created
  after_update_commit  :log_update_activity
  after_update_commit  :broadcast_updated
  after_update_commit  :spawn_next_recurrence_on_completion
  after_destroy_commit :broadcast_destroyed

  # Full snapshot used by the broadcaster + REST responses. Keep this
  # cheap: scalars + small association payloads only — anything heavy
  # (full comment bodies, activity log) is fetched on demand.
  def push_event_data
    attributes_payload.merge(association_summary).merge(timestamps_payload)
  end

  def recurring?
    recurrence_rule.present? && recurrence_rule != {}
  end

  private

  def attributes_payload
    {
      id: id,
      display_id: display_id,
      account_id: account_id,
      created_by_user_id: created_by_user_id,
      title: title,
      description: description,
      status: status,
      urgency: urgency,
      due_date: due_date&.to_i,
      completed_at: completed_at&.to_i,
      notify_assignees: notify_assignees,
      custom_attributes: custom_attributes,
      position: position,
      recurrence_rule: recurrence_rule || {},
      recurrence_parent_id: recurrence_parent_id,
      next_occurrence_at: next_occurrence_at&.to_i
    }
  end

  def association_summary
    {
      assignees: assignees.map { |u| assignee_payload(u) },
      comments_count: task_comments.size,
      activities_count: task_activities.size
    }
  end

  def assignee_payload(user)
    { id: user.id, name: user.name, avatar_url: user.avatar_url }
  end

  def timestamps_payload
    { created_at: created_at.to_i, updated_at: updated_at.to_i }
  end

  def log_creation_activity
    task_activities.create!(user: created_by_user, action: 'created', payload: { title: title })
  end

  def log_update_activity
    diff = previous_changes.except('updated_at')
    return if diff.empty?

    diff.each_key do |attr|
      action = activity_action_for(attr)
      next if action.blank?

      # Stamp the actor so the activity feed shows a real name instead of
      # the generic "System" fallback. `Current.user` is set in request
      # context (dashboard + token API); it's nil only for scheduler-driven
      # updates, where "System" is the correct attribution.
      task_activities.create!(user: Current.user, action: action,
                              payload: { from: diff[attr][0], to: diff[attr][1] })
    end
  end

  ACTIVITY_ACTIONS_BY_ATTR = {
    'status' => 'status_changed',
    'due_date' => 'due_date_changed',
    'completed_at' => 'completed'
  }.freeze

  def activity_action_for(attr)
    ACTIVITY_ACTIONS_BY_ATTR[attr.to_s]
  end

  def broadcast_created
    Tasks::Broadcaster.broadcast('task.created', self, target: :account)
  end

  def broadcast_updated
    Tasks::Broadcaster.broadcast('task.updated', self, target: :account)
  end

  def broadcast_destroyed
    Tasks::Broadcaster.broadcast('task.deleted', self, target: :account, payload: { id: id })
  end

  # Spawn the next occurrence the moment a recurring task is marked done.
  # Guarded so the callback only fires when:
  #   * the status column actually flipped in this update
  #   * the new status is `done` (cancelled/blocked don't roll forward)
  #   * the rule is present (skip if recurrence was disabled in-flight)
  # The Job + RecurrenceGenerator handle the actual clone — the callback
  # only schedules to keep the user-visible mutation snappy.
  def spawn_next_recurrence_on_completion
    return unless saved_change_to_status?
    return unless status_done?
    return unless recurring?

    Tasks::RecurrenceGenerator.spawn_next!(self)
  rescue StandardError => e
    Rails.logger.error("[Task#spawn_next_recurrence] task=#{id} failed: #{e.message}")
  end
end

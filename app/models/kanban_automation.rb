# == Schema Information
#
# Table name: kanban_automations
#
#  id                 :bigint           not null, primary key
#  account_id         :bigint           not null
#  funnel_id          :bigint
#  name               :string           not null
#  description        :text
#  event_name         :string           not null
#  conditions         :jsonb            not null, default {}
#  actions            :jsonb            not null, default []
#  active             :boolean          not null, default true
#  run_count          :integer          not null, default 0
#  last_run_at        :datetime
#  last_error_at      :datetime
#  last_error_message :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
# Indexes:
#   index_kanban_automations_on_account_event_active
#   index_kanban_automations_on_funnel_event_active
#
class KanbanAutomation < ApplicationRecord
  # Authoritative catalogue of triggers. The dispatcher only invokes
  # rules whose `event_name` matches the dispatched event — adding a new
  # event here requires (1) wiring it from a callback / scheduled job
  # and (2) shipping the condition schema below.
  EVENTS = %w[
    task_created
    task_moved_to_stage
    task_moved_to_funnel
    task_assigned
    task_priority_changed
    task_completed
    task_overdue
    conversation_attached
  ].freeze

  # Authoritative catalogue of action types. Each maps 1:1 to a class
  # under `Kanban::Automations::Actions::<CamelCase>`. Keep this list in
  # sync with the strategy registry — anything not listed here is
  # rejected at validation time so a typo in the JSON never silently
  # disables a production rule.
  ACTION_TYPES = %w[
    send_message
    assign_user
    unassign_users
    move_to_stage
    move_to_funnel
    add_subtask
    add_label
    remove_label
    set_priority
    set_due_date
    webhook
    resolve_conversation
  ].freeze

  PRIORITIES = %w[none low medium high urgent].freeze
  MAX_ACTIONS = 20

  belongs_to :account
  belongs_to :funnel, optional: true

  validates :name, presence: true, length: { maximum: 120 }
  validates :description, length: { maximum: 2000 }, allow_blank: true
  validates :event_name, presence: true, inclusion: { in: EVENTS }
  validate  :validate_funnel_belongs_to_account
  validate  :validate_conditions_shape
  validate  :validate_actions_shape

  scope :active, -> { where(active: true) }
  scope :for_event, ->(event) { where(event_name: event) }
  scope :for_account, ->(account_id) { where(account_id: account_id) }
  scope :for_funnel_or_account_wide, lambda { |funnel_id|
    where('funnel_id = :fid OR funnel_id IS NULL', fid: funnel_id)
  }

  # Convenience accessor used by specs + the executor — actions are
  # stored as a JSONB array of hashes; this keeps the executor from
  # littering itself with `Array(actions).map(...)` defensive copies.
  def actions_array
    Array(actions).map { |action| action.is_a?(Hash) ? action.with_indifferent_access : {} }
  end

  # Record a successful run for observability + simple rate-limit /
  # debounce logic downstream. Uses `update_columns` to skip callbacks
  # so this can be called from inside the executor without triggering
  # a recursive automation cascade.
  # rubocop:disable Rails/SkipsModelValidations
  def record_run!
    update_columns(
      run_count: run_count + 1,
      last_run_at: Time.current,
      last_error_at: nil,
      last_error_message: nil,
      updated_at: Time.current
    )
  end

  def record_error!(message)
    update_columns(
      last_error_at: Time.current,
      last_error_message: message.to_s.truncate(500),
      updated_at: Time.current
    )
  end
  # rubocop:enable Rails/SkipsModelValidations

  def push_event_data
    {
      id: id,
      account_id: account_id,
      funnel_id: funnel_id,
      name: name,
      description: description,
      event_name: event_name,
      conditions: conditions,
      actions: actions_array,
      active: active,
      run_count: run_count,
      last_run_at: last_run_at&.to_i,
      last_error_at: last_error_at&.to_i,
      last_error_message: last_error_message,
      created_at: created_at.to_i,
      updated_at: updated_at.to_i
    }
  end

  private

  def validate_funnel_belongs_to_account
    return if funnel.blank?
    return if funnel.account_id == account_id

    errors.add(:funnel, 'must belong to the same account')
  end

  # Conditions are loose by design (different events expose different
  # filterable attributes), but we enforce the shape: must be a Hash with
  # string keys mapping to either a primitive or an array of primitives.
  def validate_conditions_shape
    return errors.add(:conditions, 'must be an object') unless conditions.is_a?(Hash)
    return if conditions.empty?

    invalid = conditions.reject { |_, v| primitive_or_array?(v) }.keys
    return if invalid.empty?

    errors.add(:conditions, "unsupported value type for keys: #{invalid.join(', ')}")
  end

  def validate_actions_shape
    return errors.add(:actions, 'must be an array') unless actions.is_a?(Array)
    return errors.add(:actions, "max #{MAX_ACTIONS} actions per rule") if actions.length > MAX_ACTIONS

    actions.each_with_index { |action, idx| validate_single_action(action, idx) }
  end

  def validate_single_action(action, idx)
    unless action.is_a?(Hash)
      errors.add(:actions, "[#{idx}] must be an object")
      return
    end

    type = action['type'] || action[:type]
    return if ACTION_TYPES.include?(type.to_s)

    errors.add(:actions, "[#{idx}] unknown type: #{type.inspect}")
  end

  def primitive_or_array?(value)
    return true if [String, Integer, Float, TrueClass, FalseClass, NilClass].any? { |klass| value.is_a?(klass) }
    return true if value.is_a?(Array) && value.all? { |v| [String, Integer, Float].any? { |k| v.is_a?(k) } }

    false
  end
end

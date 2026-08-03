# == Schema Information
#
# Table name: conversations
#
#  id                     :integer          not null, primary key
#  additional_attributes  :jsonb
#  agent_last_seen_at     :datetime
#  assignee_last_seen_at  :datetime
#  cached_label_list      :text
#  contact_last_seen_at   :datetime
#  custom_attributes      :jsonb
#  first_reply_created_at :datetime
#  identifier             :string
#  last_activity_at       :datetime         not null
#  priority               :integer
#  snoozed_until          :datetime
#  status                 :integer          default("open"), not null
#  uuid                   :uuid             not null
#  waiting_since          :datetime
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :integer          not null
#  assignee_agent_bot_id  :bigint
#  assignee_id            :integer
#  campaign_id            :bigint
#  contact_id             :bigint
#  contact_inbox_id       :bigint
#  display_id             :integer          not null
#  inbox_id               :integer          not null
#  sla_policy_id          :bigint
#  team_id                :bigint
#
# Indexes
#
#  conv_acid_inbid_stat_asgnid_idx                    (account_id,inbox_id,status,assignee_id)
#  index_conversations_on_account_id                  (account_id)
#  index_conversations_on_account_id_and_display_id   (account_id,display_id) UNIQUE
#  index_conversations_on_assignee_id_and_account_id  (assignee_id,account_id)
#  index_conversations_on_campaign_id                 (campaign_id)
#  index_conversations_on_contact_id                  (contact_id)
#  index_conversations_on_contact_inbox_id            (contact_inbox_id)
#  index_conversations_on_first_reply_created_at      (first_reply_created_at)
#  index_conversations_on_id_and_account_id           (account_id,id)
#  index_conversations_on_identifier_and_account_id   (identifier,account_id)
#  index_conversations_on_inbox_id                    (inbox_id)
#  index_conversations_on_priority                    (priority)
#  index_conversations_on_status_and_account_id       (status,account_id)
#  index_conversations_on_status_and_priority         (status,priority)
#  index_conversations_on_team_id                     (team_id)
#  index_conversations_on_uuid                        (uuid) UNIQUE
#  index_conversations_on_waiting_since               (waiting_since)
#

class Conversation < ApplicationRecord
  include Labelable
  include LlmFormattable
  include AssignmentHandler
  include AutoAssignmentHandler
  include ActivityMessageHandler
  include UrlHelper
  include SortHandler
  include PushDataHelper

  # Override SortHandler's sort scopes so pinned conversations float to
  # the top of every list regardless of which sort the operator picked.
  # All column references are qualified with the `conversations.` table
  # name — without that, the DISTINCT auto-promotion of ORDER BY terms
  # exposes ambiguity against any join that brings in another
  # `last_activity_at` column (mentions, messages-grouped views, etc).
  class << self
    def sort_on_last_activity_at(sort_direction = :desc)
      order(pinned_order_sql("conversations.last_activity_at #{sort_direction.to_s.upcase}"))
    end

    def sort_on_created_at(sort_direction = :asc)
      order(pinned_order_sql("conversations.created_at #{sort_direction.to_s.upcase}"))
    end

    def sort_on_priority(sort_direction = :desc)
      order(pinned_order_sql("conversations.priority #{sort_direction.to_s.upcase} NULLS LAST, conversations.last_activity_at DESC"))
    end

    def sort_on_priority_created_at(sort_direction = :desc)
      order(pinned_order_sql("conversations.priority #{sort_direction.to_s.upcase} NULLS LAST, conversations.created_at ASC"))
    end

    def sort_on_waiting_since(sort_direction = :asc)
      order(pinned_order_sql(
              "(conversations.waiting_since IS NULL), conversations.waiting_since #{sort_direction.to_s.upcase}, conversations.created_at ASC"
            ))
    end

    private

    def pinned_order_sql(suffix)
      Arel::Nodes::SqlLiteral.new(
        sanitize_sql_for_order(
          "conversations.pinned_at IS NULL, conversations.pinned_at DESC, #{suffix}"
        )
      )
    end
  end
  include ConversationMuteHelpers

  validates :account_id, presence: true
  validates :inbox_id, presence: true
  validates :contact_id, presence: true
  before_validation :validate_additional_attributes
  before_validation :reset_agent_bot_when_assignee_present
  validates :additional_attributes, jsonb_attributes_length: true
  validates :custom_attributes, jsonb_attributes_length: true
  validates :uuid, uniqueness: true
  validate :validate_referer_url
  validate :ai_assistant_belongs_to_same_account

  enum status: { open: 0, resolved: 1, pending: 2, snoozed: 3 }
  enum priority: { low: 0, medium: 1, high: 2, urgent: 3 }

  # Athenas test-playground conversations. They are real conversations (so the
  # agent runs against the exact production code path) but must never appear
  # next to real customers in the inbox.
  # Column MUST be table-qualified: `contacts` also has an additional_attributes
  # column, so a bare reference is ambiguous the moment the query joins them.
  scope :not_sandbox, -> { where("conversations.additional_attributes->>'athenas_sandbox' IS NULL") }

  # A test-playground conversation is not real traffic: it must never reach a
  # customer's webhook, trigger an automation rule or start a chatflow.
  def sandbox?
    additional_attributes.is_a?(Hash) && additional_attributes['athenas_sandbox'].present?
  end
  scope :unassigned, -> { where(assignee_id: nil) }
  scope :assigned, -> { where.not(assignee_id: nil) }
  scope :assigned_to, ->(agent) { where(assignee_id: agent.id) }
  scope :unattended, -> { where(first_reply_created_at: nil).or(where.not(waiting_since: nil)) }
  # UniverZAP semantics:
  # - waiting       = no agent reply yet (conversation still awaiting first response).
  # - in_attendance = agent has already replied at least once.
  scope :waiting, -> { where(first_reply_created_at: nil) }
  scope :in_attendance, -> { where.not(first_reply_created_at: nil) }
  # UniverZAP: WhatsApp group chats (contact identifier ends with "@g.us") are
  # bucketed into a dedicated "Grupos" tab and excluded from the regular tabs
  # to cut visual noise. `is_group` is set on create (see set_group_flag) and
  # backfilled by the migration.
  scope :groups, -> { where(is_group: true) }
  scope :non_groups, -> { where(is_group: false) }
  scope :resolvable_not_waiting, lambda { |auto_resolve_after|
    return none if auto_resolve_after.to_i.zero?

    open.where('last_activity_at < ? AND waiting_since IS NULL', Time.now.utc - auto_resolve_after.minutes)
  }
  scope :resolvable_all, lambda { |auto_resolve_after|
    return none if auto_resolve_after.to_i.zero?

    open.where('last_activity_at < ?', Time.now.utc - auto_resolve_after.minutes)
  }

  scope :last_user_message_at, lambda {
    joins(
      "INNER JOIN (#{last_messaged_conversations.to_sql}) AS grouped_conversations
      ON grouped_conversations.conversation_id = conversations.id"
    ).sort_on_last_user_message_at
  }

  belongs_to :account
  belongs_to :inbox
  belongs_to :assignee, class_name: 'User', optional: true, inverse_of: :assigned_conversations
  belongs_to :assignee_agent_bot, class_name: 'AgentBot', optional: true
  belongs_to :ai_assistant, class_name: 'Ai::Assistant', optional: true
  belongs_to :contact
  belongs_to :contact_inbox
  belongs_to :team, optional: true
  belongs_to :campaign, optional: true

  has_many :mentions, dependent: :destroy_async
  has_many :messages, dependent: :destroy_async, autosave: true
  has_one :csat_survey_response, dependent: :destroy_async
  has_many :conversation_participants, dependent: :destroy_async
  has_many :notifications, as: :primary_actor, dependent: :destroy_async
  has_many :attachments, through: :messages
  has_many :reporting_events, dependent: :destroy_async
  has_many :kanban_task_conversations, dependent: :destroy
  has_many :kanban_tasks, through: :kanban_task_conversations

  before_save :ensure_snooze_until_reset
  before_create :determine_conversation_status
  before_create :ensure_waiting_since
  before_create :set_group_flag
  before_destroy :scrub_ai_response_log

  after_update_commit :execute_after_update_commit_callbacks
  after_create_commit :notify_conversation_creation
  after_create_commit :load_attributes_created_by_db_triggers

  delegate :auto_resolve_after, to: :account

  def can_reply?
    Conversations::MessageWindowService.new(self).can_reply?
  end

  def language
    additional_attributes&.dig('conversation_language')
  end

  # Cumulative Athenas cost for this conversation in BRL cents. We
  # aggregate `ai_invocations.cost_usd` (what Anthropic billed us) and
  # apply the same FX + markup the pricing calculator uses for the
  # paywall modal. Exposed in the conversation jbuilder so the
  # dashboard can show a per-conversation "atendimento custou R$X,XX"
  # chip without an extra round-trip. Returns 0 when no invocations
  # have run yet — typical for human-only conversations.
  def athenas_cost_cents_brl
    total_usd = Ai::Invocation.where(conversation_id: id).sum(:cost_usd).to_f
    return 0 if total_usd <= 0

    brl = total_usd *
          Ai::PricingCalculator::USD_TO_BRL_RATE *
          Ai::PricingCalculator::DEFAULT_MARKUP
    (brl * Ai::PricingCalculator::CENTS_PER_REAL).round
  end

  # Be aware: The precision of created_at and last_activity_at may differ from Ruby's Time precision.
  # Our DB column (see schema) stores timestamps with second-level precision (no microseconds), so
  # if you assign a Ruby Time with microseconds, the DB will truncate it. This may cause subtle differences
  # if you compare or copy these values in Ruby, also in our specs
  # So in specs rely on to be_with(1.second) instead of to eq()
  # TODO: Migrate to use a timestamp with microsecond precision
  def last_activity_at
    self[:last_activity_at] || created_at
  end

  def last_incoming_message
    messages.where(account_id: account_id)&.incoming&.last
  end

  def toggle_status
    # FIXME: implement state machine with aasm
    self.status = open? ? :resolved : :open
    self.status = :open if pending? || snoozed?
    save
  end

  def toggle_priority(priority = nil)
    self.priority = priority.presence
    save
  end

  # Pin = float the conversation to the top of every sorted list for
  # every agent in the account. Storing the timestamp gives us a free
  # ordering among multiple pinned chats (most recent on top).
  def toggle_pin!
    update!(pinned_at: pinned_at.present? ? nil : Time.current)
  end

  def bot_handoff!
    update(waiting_since: Time.current) if waiting_since.blank?
    open!
    dispatcher_dispatch(CONVERSATION_BOT_HANDOFF)
  end

  def unread_messages
    agent_last_seen_at.present? ? messages.created_since(agent_last_seen_at) : messages
  end

  def assignee_unread_messages
    assignee_last_seen_at.present? ? messages.created_since(assignee_last_seen_at) : messages
  end

  def unread_incoming_messages
    unread_messages.where(account_id: account_id).incoming.last(10)
  end

  def cached_label_list_array
    (cached_label_list || '').split(',').map(&:strip)
  end

  def notifiable_assignee_change?
    return false unless saved_change_to_assignee_id?
    return false if assignee_id.blank?
    return false if self_assign?(assignee_id)

    true
  end

  # Virtual attribute till we switch completely to polymorphic assignee
  def assignee_type
    return 'AgentBot' if assignee_agent_bot_id.present?
    return 'User' if assignee_id.present?

    nil
  end

  def assigned_entity
    assignee_agent_bot || assignee
  end

  def tweet?
    inbox.inbox_type == 'Twitter' && additional_attributes['type'] == 'tweet'
  end

  def recent_messages
    messages.chat.last(5)
  end

  def csat_survey_link
    "#{ENV.fetch('FRONTEND_URL', nil)}/survey/responses/#{uuid}"
  end

  def dispatch_conversation_updated_event(previous_changes = nil)
    dispatcher_dispatch(CONVERSATION_UPDATED, previous_changes)
  end

  private

  # LGPD art. 18: the AI response log snapshots what the customer wrote and what
  # the agent answered, so deleting a conversation has to take that text with
  # it. Only the text is cleared — tokens, cost and latency stay, because the
  # operator's billing history must survive a data-subject deletion. The rows
  # are not associated (conversation_id is a plain column, no FK), so an
  # association with `dependent:` would not fire here.
  def scrub_ai_response_log
    # rubocop:disable Rails/SkipsModelValidations
    Ai::Invocation.where(conversation_id: id)
                  .update_all(user_message: nil, ai_response: nil, system_prompt: nil)
    # rubocop:enable Rails/SkipsModelValidations
  rescue StandardError => e
    Rails.logger.error("[Athenas] could not scrub AI log for conversation=#{id}: #{e.message}")
  end

  def execute_after_update_commit_callbacks
    handle_resolved_status_change
    notify_status_change
    create_activity
    notify_conversation_updation
  end

  def handle_resolved_status_change
    # When conversation is resolved, clear waiting_since using update_column to avoid callbacks
    return unless saved_change_to_status? && status == 'resolved'

    # rubocop:disable Rails/SkipsModelValidations
    update_column(:waiting_since, nil)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def ensure_snooze_until_reset
    self.snoozed_until = nil unless snoozed?
  end

  def ensure_waiting_since
    self.waiting_since = created_at
  end

  # WhatsApp group jids end with "@g.us". The WAHA connector sets the group id
  # as the contact identifier, so a conversation is a group when its contact's
  # identifier matches. Computed once on create; backfilled for existing rows.
  def set_group_flag
    self.is_group = contact&.identifier.to_s.end_with?('@g.us')
    true
  end

  def validate_additional_attributes
    self.additional_attributes = {} unless additional_attributes.is_a?(Hash)
  end

  def reset_agent_bot_when_assignee_present
    return if assignee_id.blank?

    self.assignee_agent_bot_id = nil
  end

  def determine_conversation_status
    self.status = :resolved and return if contact.blocked?

    return handle_campaign_status if campaign.present?

    # TODO: make this an inbox config instead of assuming bot conversations should start as pending
    self.status = :pending if inbox.active_bot?
  end

  def handle_campaign_status
    # If campaign has no sender (bot-initiated) and inbox has active bot, let bot handle it
    self.status = :pending if campaign.sender_id.nil? && inbox.active_bot?
  end

  def notify_conversation_creation
    dispatcher_dispatch(CONVERSATION_CREATED)
  end

  def notify_conversation_updation
    return unless previous_changes.keys.present? && allowed_keys?

    dispatch_conversation_updated_event(previous_changes)
  end

  def list_of_keys
    %w[team_id assignee_id assignee_agent_bot_id status snoozed_until custom_attributes label_list waiting_since
       first_reply_created_at priority]
  end

  def allowed_keys?
    (
      previous_changes.keys.intersect?(list_of_keys) ||
      (previous_changes['additional_attributes'].present? && previous_changes['additional_attributes'][1].keys.include?('conversation_language'))
    )
  end

  def load_attributes_created_by_db_triggers
    # Display id is set via a trigger in the database
    # So we need to specifically fetch it after the record is created
    # We can't use reload because it will clear the previous changes, which we need for the dispatcher
    obj_from_db = self.class.find(id)
    self[:display_id] = obj_from_db[:display_id]
    self[:uuid] = obj_from_db[:uuid]
  end

  def notify_status_change
    {
      CONVERSATION_OPENED => -> { saved_change_to_status? && open? },
      CONVERSATION_RESOLVED => -> { saved_change_to_status? && resolved? },
      CONVERSATION_STATUS_CHANGED => -> { saved_change_to_status? },
      CONVERSATION_READ => -> { saved_change_to_contact_last_seen_at? },
      CONVERSATION_CONTACT_CHANGED => -> { saved_change_to_contact_id? }
    }.each do |event, condition|
      condition.call && dispatcher_dispatch(event, status_change)
    end
  end

  def dispatcher_dispatch(event_name, changed_attributes = nil)
    Rails.configuration.dispatcher.dispatch(event_name, Time.zone.now, conversation: self, notifiable_assignee_change: notifiable_assignee_change?,
                                                                       changed_attributes: changed_attributes,
                                                                       performed_by: Current.executed_by)
  end

  def conversation_status_changed_to_open?
    return false unless open?
    # saved_change_to_status? method only works in case of update
    return true if previous_changes.key?(:id) || saved_change_to_status?
  end

  def create_label_change(user_name)
    return unless user_name

    previous_labels, current_labels = previous_changes[:label_list]
    return unless (previous_labels.is_a? Array) && (current_labels.is_a? Array)

    create_label_added(user_name, current_labels - previous_labels)
    create_label_removed(user_name, previous_labels - current_labels)
  end

  def validate_referer_url
    return unless additional_attributes['referer']

    self['additional_attributes']['referer'] = nil unless url_valid?(additional_attributes['referer'])
  end

  # Tenant safety: a conversation must never be bound to an AI assistant from a
  # different account (Athenas would then reply with another tenant's knowledge
  # base and bill their credits). Primary backstop for every write path; the
  # controller scoping and the autopilot job guard are defense-in-depth.
  def ai_assistant_belongs_to_same_account
    return if ai_assistant_id.blank?
    return if ai_assistant&.account_id == account_id

    errors.add(:ai_assistant, 'must belong to the same account')
  end

  # creating db triggers
  trigger.before(:insert).for_each(:row) do
    "NEW.display_id := nextval('conv_dpid_seq_' || NEW.account_id);"
  end
end

Conversation.include_mod_with('Audit::Conversation')
Conversation.include_mod_with('Concerns::Conversation')
Conversation.prepend_mod_with('Conversation')

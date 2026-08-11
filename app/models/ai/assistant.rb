# == Schema Information
#
# Table name: ai_assistants
#
class Ai::Assistant < ApplicationRecord
  self.table_name = 'ai_assistants'

  belongs_to :account
  has_many :trainings, class_name: 'Ai::Training', foreign_key: :ai_assistant_id, inverse_of: :ai_assistant, dependent: :destroy
  has_many :intents, class_name: 'Ai::Intent', foreign_key: :ai_assistant_id, inverse_of: :ai_assistant, dependent: :destroy
  # `ai_invocations.ai_assistant_id` is NOT NULL in the schema, so `:nullify`
  # blows up on destroy. Cascade deletion keeps the table consistent.
  has_many :invocations, class_name: 'Ai::Invocation', foreign_key: :ai_assistant_id, inverse_of: :ai_assistant, dependent: :destroy
  has_many :custom_tools, class_name: 'Ai::CustomTool', foreign_key: :ai_assistant_id, inverse_of: :ai_assistant, dependent: :destroy
  # Scheduling. All `:destroy` so removing an agent cannot trip over a foreign
  # key the way it did twice before; the Google events survive regardless.
  has_many :calendar_connections, class_name: 'Ai::Calendar::Connection', foreign_key: :ai_assistant_id,
                                  inverse_of: :ai_assistant, dependent: :destroy
  has_many :calendar_professionals, class_name: 'Ai::Calendar::Professional', foreign_key: :ai_assistant_id,
                                    inverse_of: :ai_assistant, dependent: :destroy
  has_many :calendar_services, class_name: 'Ai::Calendar::Service', foreign_key: :ai_assistant_id,
                               inverse_of: :ai_assistant, dependent: :destroy
  has_many :calendar_appointments, class_name: 'Ai::Calendar::Appointment', foreign_key: :ai_assistant_id,
                                   inverse_of: :ai_assistant, dependent: :destroy
  has_one :calendar_setting, class_name: 'Ai::Calendar::Setting', foreign_key: :ai_assistant_id,
                             inverse_of: :ai_assistant, dependent: :destroy
  has_many :inboxes, foreign_key: :ai_assistant_id, inverse_of: :ai_assistant, dependent: :nullify
  has_many :conversations, foreign_key: :ai_assistant_id, inverse_of: :ai_assistant, dependent: :nullify
  has_many :chat_threads, class_name: 'Ai::ChatThread', foreign_key: :ai_assistant_id,
                          inverse_of: :ai_assistant, dependent: :destroy
  has_many :response_feedbacks, class_name: 'Ai::ResponseFeedback', foreign_key: :ai_assistant_id,
                                inverse_of: :ai_assistant, dependent: :destroy
  has_many :prompt_versions, class_name: 'Ai::PromptVersion', foreign_key: :ai_assistant_id,
                             inverse_of: :ai_assistant, dependent: :destroy
  has_many :ab_comparisons, class_name: 'Ai::AbComparison', foreign_key: :ai_assistant_id,
                            inverse_of: :ai_assistant, dependent: :destroy
  has_many :lead_opportunities, class_name: 'Ai::LeadOpportunity', foreign_key: :ai_assistant_id,
                                inverse_of: :ai_assistant, dependent: :destroy
  has_many :revenue_events, class_name: 'Ai::RevenueEvent', foreign_key: :ai_assistant_id,
                            inverse_of: :ai_assistant, dependent: :destroy
  # A used agent has history rows behind a NOT NULL FK, so destroy blew up with a
  # foreign-key violation (the 500 on delete) until they were cleared first. It
  # is a pure projection with no destroy callbacks, so delete_all clears the
  # whole window in one statement.
  has_many :response_histories, class_name: 'Ai::ResponseHistory', foreign_key: :ai_assistant_id,
                                inverse_of: :ai_assistant, dependent: :delete_all

  # The instructions the agent actually runs on. Falls back to the mutable
  # column so an agent that was never versioned keeps behaving identically.
  def live_prompt_version
    prompt_versions.live.first
  end

  def effective_system_prompt
    live_prompt_version&.system_prompt.presence || system_prompt
  end

  def effective_few_shots
    live_prompt_version&.few_shot_pairs || []
  end

  def effective_prompt_version
    live_prompt_version&.version || Ai::KnowledgeGrounding::PROMPT_VERSION
  end

  PROVIDERS = %w[anthropic openai].freeze
  TONES = %w[friendly formal sales support concierge].freeze

  encrypts :encrypted_anthropic_key, deterministic: false if Chatwoot.encryption_configured?
  encrypts :encrypted_openai_key, deterministic: false if Chatwoot.encryption_configured?
  encrypts :encrypted_elevenlabs_key, deterministic: false if Chatwoot.encryption_configured?

  validates :name, presence: true, length: { maximum: 80 }, uniqueness: { scope: :account_id, case_sensitive: false }
  validates :provider, inclusion: { in: PROVIDERS }
  validates :temperature, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 2 }
  validates :max_tokens, numericality: { greater_than: 0, less_than_or_equal_to: 8192 }
  validates :tone, inclusion: { in: TONES }, allow_blank: true

  scope :active, -> { where(active: true) }

  def resolved_anthropic_key
    encrypted_anthropic_key.presence || ENV.fetch('ANTHROPIC_API_KEY', nil)
  end

  def resolved_openai_key
    encrypted_openai_key.presence || ENV.fetch('OPENAI_API_KEY', nil)
  end

  def resolved_elevenlabs_key
    encrypted_elevenlabs_key.presence || ENV.fetch('ELEVENLABS_API_KEY', nil)
  end

  def autopilot?
    autopilot_enabled?
  end

  # Per-agent opt-in for the "human-like reply" behaviors (Slices 1-3). Reads the
  # behavior_flags jsonb; an unset flag is simply off.
  def behavior_flag?(key)
    ActiveModel::Type::Boolean.new.cast(behavior_flags_payload[key.to_s])
  end

  # The one behaviour that is ON until somebody turns it off, so it cannot use
  # behavior_flag? — an unset flag there means "off", and off here means the
  # agent starts answering group chats.
  #
  # A group is several people talking to each other, not a customer talking to
  # the shop: the agent has no way to know which messages are addressed to it,
  # and answering them all is the fastest way to get the number reported. Every
  # agent that already exists reads `nil` and gets the safe behaviour without
  # anyone touching it.
  def skip_groups?
    value = behavior_flags_payload['skip_groups']
    return true if value.nil?

    ActiveModel::Type::Boolean.new.cast(value)
  end

  def push_event_data
    identity_payload.merge(model_payload).merge(behavior_payload).merge(meta_payload)
  end

  private

  def identity_payload
    {
      id: id,
      name: name,
      conversation_display_name: conversation_display_name,
      role: role,
      description: description,
      avatar_url: avatar_url,
      tone: tone,
      # The dashboard edit screen needs to render the prompt for review,
      # but the encrypted provider keys should never leave the server in
      # plaintext — surface a boolean flag instead so the UI can show a
      # "key configured" badge without leaking the secret itself.
      system_prompt: system_prompt,
      has_anthropic_key: encrypted_anthropic_key.present?,
      has_openai_key: encrypted_openai_key.present?
    }
  end

  def model_payload
    {
      provider: provider,
      model: model,
      temperature: temperature,
      max_tokens: max_tokens,
      router_config: router_config
    }
  end

  def behavior_payload
    {
      autopilot_enabled: autopilot_enabled,
      behavior_flags: behavior_flags_payload,
      guardrails: guardrails,
      active: active
    }
  end

  # Tolerates the column not existing yet: the flags migration is applied by
  # hand on prod, so a code deploy that lands before it must not break assistant
  # serialization the way the missing ai_custom_tools table once did.
  def behavior_flags_payload
    return {} unless has_attribute?(:behavior_flags)

    behavior_flags || {}
  end

  def meta_payload
    {
      created_at: created_at.to_i,
      updated_at: updated_at.to_i,
      stats: {
        # Prefer the per-row counts injected by `index` (left_joins + select)
        # so we stay zero-query in list responses. Fall back to `.count` for
        # member actions / show pages where the eager counts are absent.
        trainings_count: attributes['trainings_count']&.to_i || trainings.count,
        intents_count: attributes['intents_count']&.to_i || intents.count,
        invocations_count: attributes['invocations_count']&.to_i || invocations.count
      }
    }
  end
end

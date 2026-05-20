# == Schema Information
#
# Table name: ai_assistants
#
class Ai::Assistant < ApplicationRecord
  self.table_name = 'ai_assistants'

  belongs_to :account
  has_many :trainings, class_name: 'Ai::Training', foreign_key: :ai_assistant_id, inverse_of: :ai_assistant, dependent: :destroy
  has_many :intents, class_name: 'Ai::Intent', foreign_key: :ai_assistant_id, inverse_of: :ai_assistant, dependent: :destroy
  has_many :invocations, class_name: 'Ai::Invocation', foreign_key: :ai_assistant_id, inverse_of: :ai_assistant, dependent: :nullify
  has_many :inboxes, foreign_key: :ai_assistant_id, inverse_of: :ai_assistant, dependent: :nullify
  has_many :conversations, foreign_key: :ai_assistant_id, inverse_of: :ai_assistant, dependent: :nullify
  has_many :chat_threads, class_name: 'Ai::ChatThread', foreign_key: :ai_assistant_id,
                          inverse_of: :ai_assistant, dependent: :destroy

  PROVIDERS = %w[anthropic openai].freeze
  TONES = %w[friendly formal sales support concierge].freeze

  encrypts :encrypted_anthropic_key, deterministic: false if Chatwoot.encryption_configured?
  encrypts :encrypted_openai_key, deterministic: false if Chatwoot.encryption_configured?

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

  def autopilot?
    autopilot_enabled?
  end

  def push_event_data
    identity_payload.merge(model_payload).merge(behavior_payload).merge(meta_payload)
  end

  private

  def identity_payload
    {
      id: id,
      name: name,
      role: role,
      description: description,
      avatar_url: avatar_url,
      tone: tone
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
      guardrails: guardrails,
      active: active
    }
  end

  def meta_payload
    {
      created_at: created_at.to_i,
      updated_at: updated_at.to_i,
      stats: {
        trainings_count: trainings.size,
        intents_count: intents.size,
        invocations_count: invocations.size
      }
    }
  end
end

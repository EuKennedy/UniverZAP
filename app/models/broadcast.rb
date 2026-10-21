# == Schema Information
#
# Table name: broadcasts
#
#  id           :bigint           not null, primary key
#  account_id   :bigint           not null
#  inbox_id     :bigint
#  name         :string           not null
#  mode         :string           default("waha"), not null
#  status       :integer          default(0), not null
#  message      :jsonb            default({})
#  audience     :jsonb            default({})
#  throttle     :jsonb            default({})
#  scheduled_at :datetime
#  pause_reason :string
#  cold_contacts_confirmed_at    :datetime
#  cold_contacts_confirmed_by_id :bigint
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
# A broadcast is a mass WhatsApp dispatch, in one of two modes.
# `waha`     — free text through MessageBuilder, so it renders inside Chatwoot
#              AND dispatches to WhatsApp via the WAHA connector.
# `official` — an approved template through the Meta Cloud API.
class Broadcast < ApplicationRecord
  belongs_to :account
  # Inbox is chosen later in the composer, so a fresh broadcast starts without one.
  belongs_to :inbox, optional: true

  has_many :broadcast_recipients, dependent: :destroy

  # draft     — being composed, never dispatches.
  # scheduled — queued for a future scheduled_at.
  # running   — actively dispatching batches.
  # paused    — halted mid-flight; no new batches.
  # completed — every recipient processed.
  enum status: { draft: 0, scheduled: 1, running: 2, paused: 3, completed: 4 }, _prefix: :status

  MODES = %w[waha official].freeze

  validates :name, presence: true
  validates :mode, inclusion: { in: MODES }
  validate :mode_matches_inbox
  before_save :forget_cold_confirmation, if: -> { audience_changed? && !cold_contacts_confirmed_at_changed? }

  def message_text
    message['text']
  end

  def audience_filters
    audience || {}
  end

  # Cadência anti-bloqueio (número não oficial). Os padrões são conservadores
  # de propósito: uma mensagem por vez, com intervalo aleatório, só no horário
  # comercial do salão e com teto por conexão — não por disparo — para que dois
  # disparos simultâneos não somem o dobro no mesmo número.
  THROTTLE_DEFAULTS = {
    'batch_min' => 1, 'batch_max' => 1,
    'delay_min' => 45, 'delay_max' => 150,
    'hourly_cap' => 30, 'daily_cap' => 150,
    'window_start' => 9, 'window_end' => 19,
    'quiet_hours' => 12, 'max_failures' => 3
  }.freeze
  # Teto que o formulário não fura: um disparo antigo salvo com 500/dia ou
  # rajada de 8 continua funcionando, só que dentro destes limites.
  HARD_LIMITS = {
    'batch_max' => 1..3, 'batch_min' => 1..3, 'delay_min' => 20..3600, 'delay_max' => 20..3600,
    'hourly_cap' => 1..60, 'daily_cap' => 1..300, 'window_start' => 0..23, 'window_end' => 1..24,
    'quiet_hours' => 0..168, 'max_failures' => 1..20
  }.freeze
  # Segunda a sábado (0 = domingo).
  DEFAULT_WEEKDAYS = [1, 2, 3, 4, 5, 6].freeze

  THROTTLE_DEFAULTS.each_key do |key|
    define_method(key) { throttle_value(key, THROTTLE_DEFAULTS[key]) }
  end

  def weekdays
    days = Array((throttle || {})['weekdays']).map(&:to_i) & (0..6).to_a
    days.presence || DEFAULT_WEEKDAYS
  end

  # Cada contato recebe no horário em que costuma responder (dentro da janela).
  def smart_timing?
    ActiveModel::Type::Boolean.new.cast((throttle || {})['smart_timing']) || false
  end

  # "Estes contatos nunca falaram com o salão" — confirmado no editor por um
  # administrador. Sem isso, o público deixa esses contatos de fora.
  def cold_contacts_confirmed?
    cold_contacts_confirmed_at.present?
  end

  def confirm_cold_contacts!(user, confirmed)
    assign_attributes(cold_contacts_confirmed_at: confirmed ? Time.current : nil, cold_contacts_confirmed_by_id: confirmed ? user&.id : nil)
  end

  def send_window
    Broadcasts::SendWindow.new(account: account, start_hour: window_start, end_hour: window_end, weekdays: weekdays)
  end

  private

  # A confirmação vale para o público que a pessoa viu. Mudou o público,
  # pede de novo.
  def forget_cold_confirmation
    self.cold_contacts_confirmed_at = nil
    self.cold_contacts_confirmed_by_id = nil
  end

  # The modes speak different protocols: `official` ships an approved template
  # through the Cloud API, `waha` ships free text. Crossing them fails silently
  # — free text on a Cloud inbox is refused outside the 24h window, and the
  # recipient was marked sent anyway.
  def mode_matches_inbox
    return if inbox.blank?
    # Only judge the pair when somebody actually sets it. Rows that predate this
    # rule would otherwise fail on status_completed! and leave the broadcast
    # stuck in `running` after every recipient was already sent.
    return unless mode_changed? || inbox_id_changed?

    mismatch = mode_mismatch
    errors.add(:mode, mismatch) if mismatch
  end

  # Why the mode and the inbox disagree, or nil when they are a valid pair.
  def mode_mismatch
    cloud = cloud_inbox?
    return 'official requires a WhatsApp Cloud inbox' if mode == 'official' && !cloud
    return 'waha cannot send free text on a WhatsApp Cloud inbox' if mode == 'waha' && cloud

    nil
  end

  def cloud_inbox?
    channel = inbox.channel
    channel.is_a?(Channel::Whatsapp) && channel.provider == 'whatsapp_cloud'
  end

  def throttle_value(key, fallback)
    value = (throttle || {})[key]
    value = value.presence ? value.to_i : fallback
    range = HARD_LIMITS[key]
    range ? value.clamp(range) : value
  end
end

# == Schema Information
#
# Table name: whatsapp_status_posts
#
#  id               :bigint           not null, primary key
#  background_color :string
#  body             :text
#  font             :integer          default(0), not null
#  inbox_ids        :jsonb            not null
#  kind             :string           default("text"), not null
#  occurrence_key   :string
#  published_at     :datetime
#  recurrence       :string           default("none"), not null
#  scheduled_at     :datetime
#  status           :integer          default("draft"), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  campaign_id      :bigint
#  campaign_step_id :bigint
#  user_id          :bigint
#
# Indexes
#
#  idx_on_account_id_status_scheduled_at_e293e01cb2               (account_id,status,scheduled_at)
#  index_whatsapp_status_posts_on_account_id                      (account_id)
#  index_whatsapp_status_posts_on_campaign_id                     (campaign_id)
#  index_whatsapp_status_posts_on_campaign_id_and_occurrence_key  (campaign_id,occurrence_key) UNIQUE WHERE (occurrence_key IS NOT NULL)
#  index_whatsapp_status_posts_on_campaign_step_id                (campaign_step_id)
#  index_whatsapp_status_posts_on_user_id                         (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (campaign_id => whatsapp_status_campaigns.id) ON DELETE => nullify
#  fk_rails_...  (campaign_step_id => whatsapp_status_campaign_steps.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#
# As conexões ficam em `inbox_ids` enquanto o post ainda pode mudar. As linhas
# de WhatsappStatusDelivery só nascem na hora de publicar, porque é ali que o
# alvo vira fato: trocar as conexões de um rascunho não deixa entrega órfã.
class WhatsappStatusPost < ApplicationRecord
  KINDS = %w[text image video].freeze
  # As fontes do status de texto do WhatsApp, na ordem que a WAHA repassa ao
  # aplicativo (0 = padrão). Valores fora disso o WhatsApp ignora sem avisar.
  FONTS = (0..5).to_a.freeze
  BODY_LIMIT = 700
  HEX_COLOR = /\A#[0-9a-fA-F]{6}\z/
  # Um agendamento "para agora" chega ao servidor alguns segundos depois de o
  # operador clicar. A folga evita recusar o que, na tela, era o minuto certo.
  SCHEDULE_TOLERANCE = 2.minutes

  belongs_to :account
  belongs_to :user, optional: true
  has_many :deliveries, class_name: 'WhatsappStatusDelivery', dependent: :destroy
  belongs_to :campaign, class_name: 'WhatsappStatusCampaign', optional: true, inverse_of: :posts
  belongs_to :campaign_step, class_name: 'WhatsappStatusCampaignStep', optional: true, inverse_of: :posts
  has_one_attached :media

  # draft               — guardado para depois, nunca sai sozinho.
  # scheduled           — sai em scheduled_at pelo DueScannerJob.
  # publishing          — o job está enviando às conexões.
  # published           — saiu em todas as conexões.
  # partially_published — saiu em parte delas; as falhas podem ser reenviadas.
  # failed              — não saiu em nenhuma.
  enum status: { draft: 0, scheduled: 1, publishing: 2, published: 3, partially_published: 4, failed: 5 }, _prefix: :status

  EDITABLE_STATUSES = %w[draft scheduled].freeze
  # Repetição de um agendado: ao sair, o próximo já nasce agendado. Diário e
  # semanal cobrem "bom dia" e "promoção de terça", que é o uso do salão.
  RECURRENCE_INTERVALS = { 'daily' => 1.day, 'weekly' => 1.week }.freeze
  RECURRENCES = (['none'] + RECURRENCE_INTERVALS.keys).freeze

  validates :kind, inclusion: { in: KINDS }
  validates :font, inclusion: { in: FONTS }
  validates :recurrence, inclusion: { in: RECURRENCES }
  validates :body, length: { maximum: BODY_LIMIT }
  validates :background_color, format: { with: HEX_COLOR }, allow_blank: true
  validates :body, presence: true, if: -> { kind == 'text' && !status_draft? }
  validate :media_matches_kind, unless: -> { kind == 'text' || status_draft? }
  validate :targets_present, unless: :status_draft?
  validate :targets_belong_to_account, if: :will_save_change_to_inbox_ids?
  validates :scheduled_at, presence: true, if: :status_scheduled?
  validate :scheduled_in_future, if: -> { status_scheduled? && (will_save_change_to_scheduled_at? || will_save_change_to_status?) }

  before_validation { self.inbox_ids = Array(inbox_ids).compact_blank.map(&:to_i).uniq }

  scope :due, -> { status_scheduled.where(scheduled_at: ..Time.current) }

  def editable?
    EDITABLE_STATUSES.include?(status)
  end

  def recurring?
    RECURRENCE_INTERVALS.key?(recurrence)
  end

  # Cópia com o mesmo conteúdo e a mesma mídia (o blob é compartilhado, não
  # duplicado). Base do "Duplicar" e da próxima ocorrência de um recorrente.
  def copy(**overrides)
    copy = account.whatsapp_status_posts.new(
      slice(:user_id, :kind, :body, :background_color, :font, :inbox_ids, :recurrence, :campaign_id, :campaign_step_id).merge(overrides)
    )
    copy.media = media.blob if media.attached?
    copy
  end

  # A próxima ocorrência sai do horário combinado, não da hora em que o job
  # rodou: um scanner atrasado não empurra a série inteira.
  def schedule_next_occurrence!
    return unless recurring? && scheduled_at

    next_at = scheduled_at + RECURRENCE_INTERVALS.fetch(recurrence)
    next_at += RECURRENCE_INTERVALS.fetch(recurrence) while next_at <= Time.current
    copy(status: :scheduled, scheduled_at: next_at).tap(&:save!)
  end

  def target_inboxes
    account.inboxes.where(id: inbox_ids)
  end

  # O estado final sai das entregas, e não de quem chamou: um reenvio parcial
  # que acerta a última conexão que faltava tem que virar `published`.
  def refresh_outcome!
    statuses = deliveries.pluck(:status)
    return if statuses.include?('pending')

    outcome = outcome_for(statuses)
    update!(status: outcome, published_at: published_at || (Time.current if outcome != :failed))
  end

  private

  def outcome_for(statuses)
    return :failed if statuses.exclude?('sent')

    statuses.all?('sent') ? :published : :partially_published
  end

  def media_matches_kind
    return errors.add(:media, :blank) unless media.attached?
    return if media.blob.content_type.to_s.start_with?("#{kind}/")

    errors.add(:media, I18n.t('inbox.whatsapp.waha.media_wrong_type'))
  end

  def targets_present
    errors.add(:inbox_ids, :blank) if Array(inbox_ids).empty?
  end

  # Só conexões WAHA desta conta. Um id de outra conta ou de uma inbox de site
  # não pode chegar até o publicador, que confia nesta lista.
  def targets_belong_to_account
    ids = Array(inbox_ids).map(&:to_i)
    return if ids.empty?

    allowed = Whatsapp::WahaInboxResolver.new(account).waha_inboxes.map(&:id)
    errors.add(:inbox_ids, :invalid) unless (ids - allowed).empty?
  end

  def scheduled_in_future
    return if scheduled_at.blank? || scheduled_at > SCHEDULE_TOLERANCE.ago

    errors.add(:scheduled_at, I18n.t('inbox.whatsapp.waha.schedule_in_past'))
  end
end

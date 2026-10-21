# Campanha de status: um fluxo de passos (dia, horário, conteúdo) que sai nas
# conexões escolhidas a partir de uma data, com repostagem por passo e, se
# quiser, recomeçando o fluxo inteiro a cada N dias.
#
# A campanha não publica nada sozinha: o Planner transforma o fluxo em
# WhatsappStatusPost agendados (os mesmos do histórico e do calendário), e a
# partir dali quem publica é o caminho de sempre.
# == Schema Information
#
# Table name: whatsapp_status_campaigns
#
#  id          :bigint           not null, primary key
#  color       :string
#  cycle_days  :integer          default(0), not null
#  description :text
#  ends_on     :date
#  inbox_ids   :jsonb            not null
#  name        :string           not null
#  starts_on   :date
#  status      :integer          default("draft"), not null
#  time_zone   :string           default("America/Sao_Paulo"), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#  folder_id   :bigint
#  user_id     :bigint
#
# Indexes
#
#  index_whatsapp_status_campaigns_on_account_id             (account_id)
#  index_whatsapp_status_campaigns_on_account_id_and_status  (account_id,status)
#  index_whatsapp_status_campaigns_on_folder_id              (folder_id)
#  index_whatsapp_status_campaigns_on_user_id                (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (folder_id => whatsapp_status_folders.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#
class WhatsappStatusCampaign < ApplicationRecord
  CYCLE_OPTIONS = [0, 7, 14, 30].freeze

  belongs_to :account
  belongs_to :folder, class_name: 'WhatsappStatusFolder', optional: true, inverse_of: :campaigns
  belongs_to :user, optional: true
  has_many :steps, -> { order(:position, :id) }, class_name: 'WhatsappStatusCampaignStep', foreign_key: :campaign_id,
                                                 inverse_of: :campaign, dependent: :destroy
  has_many :posts, class_name: 'WhatsappStatusPost', foreign_key: :campaign_id, inverse_of: :campaign, dependent: :nullify

  # draft    — sendo montada, não agenda nada.
  # active   — o Planner mantém os próximos posts agendados.
  # paused   — os agendados futuros foram retirados; o histórico fica.
  # finished — campanha sem ciclo cujo último passo já saiu.
  enum status: { draft: 0, active: 1, paused: 2, finished: 3 }, _prefix: :status

  validates :name, presence: true, length: { maximum: 80 }
  validates :color, format: { with: WhatsappStatusPost::HEX_COLOR }, allow_blank: true
  validates :cycle_days, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 365 }
  validate :valid_time_zone
  validate :folder_belongs_to_account
  validate :ready_to_run, if: :status_active?

  before_validation { self.inbox_ids = Array(inbox_ids).compact_blank.map(&:to_i).uniq }

  def zone
    ActiveSupport::TimeZone[time_zone] || Time.zone
  end

  def cycling?
    cycle_days.positive?
  end

  # Tira do calendário o que ainda não saiu. Usado ao pausar, ao mudar o fluxo
  # e ao apagar: o que já foi publicado continua no histórico.
  def unschedule_future!
    posts.status_scheduled.where(scheduled_at: Time.current..).destroy_all
  end

  private

  def valid_time_zone
    errors.add(:time_zone, :invalid) if ActiveSupport::TimeZone[time_zone].nil?
  end

  def folder_belongs_to_account
    errors.add(:folder, :invalid) if folder && folder.account_id != account_id
  end

  # Ativar sem data, sem conexão ou sem passo seria uma campanha que nunca sai.
  def ready_to_run
    errors.add(:starts_on, :blank) if starts_on.blank?
    errors.add(:steps, :blank) if steps.empty?
    errors.add(:inbox_ids, :blank) if inbox_ids.empty?
    allowed = Whatsapp::WahaInboxResolver.new(account).waha_inboxes.map(&:id)
    errors.add(:inbox_ids, :invalid) unless (inbox_ids - allowed).empty?
  end
end

# Um passo do fluxo de uma campanha: o que sai, em qual dia do ciclo e a que
# horas, e quantas vezes repostar. Repostar existe porque o status some em
# 24 horas: quem quer a promoção visível a semana inteira reposta a cada 24h.
# == Schema Information
#
# Table name: whatsapp_status_campaign_steps
#
#  id                    :bigint           not null, primary key
#  background_color      :string
#  body                  :text
#  day_offset            :integer          default(0), not null
#  font                  :integer          default(0), not null
#  kind                  :string           default("text"), not null
#  position              :integer          default(0), not null
#  repost_count          :integer          default(0), not null
#  repost_interval_hours :integer          default(24), not null
#  time_of_day           :string           default("09:00"), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  campaign_id           :bigint           not null
#
# Indexes
#
#  index_whatsapp_status_campaign_steps_on_campaign_id  (campaign_id)
#
# Foreign Keys
#
#  fk_rails_...  (campaign_id => whatsapp_status_campaigns.id) ON DELETE => cascade
#
class WhatsappStatusCampaignStep < ApplicationRecord
  TIME_FORMAT = /\A([01]\d|2[0-3]):[0-5]\d\z/
  MAX_REPOSTS = 6
  REPOST_INTERVALS = [6, 12, 24, 48, 72].freeze

  belongs_to :campaign, class_name: 'WhatsappStatusCampaign', inverse_of: :steps
  has_many :posts, class_name: 'WhatsappStatusPost', foreign_key: :campaign_step_id, inverse_of: :campaign_step, dependent: :nullify
  has_one_attached :media

  validates :kind, inclusion: { in: WhatsappStatusPost::KINDS }
  validates :font, inclusion: { in: WhatsappStatusPost::FONTS }
  validates :body, length: { maximum: WhatsappStatusPost::BODY_LIMIT }
  validates :body, presence: true, if: -> { kind == 'text' }
  validates :background_color, format: { with: WhatsappStatusPost::HEX_COLOR }, allow_blank: true
  validates :time_of_day, format: { with: TIME_FORMAT }
  validates :day_offset, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than: 366 }
  validates :repost_count, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_REPOSTS }
  validates :repost_interval_hours, inclusion: { in: REPOST_INTERVALS }
  validate :media_matches_kind, unless: -> { kind == 'text' }

  # A primeira saída e as repostagens deste passo num ciclo que começa em `day`.
  def times_on(cycle_start, zone)
    hour, minute = time_of_day.split(':').map(&:to_i)
    first = zone.local(cycle_start.year, cycle_start.month, cycle_start.day, hour, minute) + day_offset.days
    (0..repost_count).map { |index| first + (index * repost_interval_hours).hours }
  end

  private

  def media_matches_kind
    return errors.add(:media, :blank) unless media.attached?
    return if media.blob.content_type.to_s.start_with?("#{kind}/")

    errors.add(:media, I18n.t('inbox.whatsapp.waha.media_wrong_type'))
  end
end

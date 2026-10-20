# == Schema Information
#
# Table name: whatsapp_status_templates
#
#  id               :bigint           not null, primary key
#  background_color :string
#  body             :text             not null
#  font             :integer          default(0), not null
#  name             :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#
# Indexes
#
#  index_whatsapp_status_templates_on_account_id           (account_id)
#  index_whatsapp_status_templates_on_account_id_and_name  (account_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#
# Modelo reutilizável de status: o texto (ou legenda) e o visual que o salão
# repete toda semana, como "agenda aberta" ou "promoção de terça".
class WhatsappStatusTemplate < ApplicationRecord
  belongs_to :account

  validates :name, presence: true, length: { maximum: 80 }, uniqueness: { scope: :account_id }
  validates :body, presence: true, length: { maximum: WhatsappStatusPost::BODY_LIMIT }
  validates :background_color, format: { with: WhatsappStatusPost::HEX_COLOR }, allow_blank: true
  validates :font, inclusion: { in: WhatsappStatusPost::FONTS }
end

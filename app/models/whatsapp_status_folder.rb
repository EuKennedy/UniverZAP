# Pasta para organizar campanhas de status ("Promoções", "Datas comemorativas").
# Apagar a pasta não apaga as campanhas: elas voltam para "Sem pasta".
# == Schema Information
#
# Table name: whatsapp_status_folders
#
#  id         :bigint           not null, primary key
#  color      :string
#  name       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#
# Indexes
#
#  index_whatsapp_status_folders_on_account_id           (account_id)
#  index_whatsapp_status_folders_on_account_id_and_name  (account_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#
class WhatsappStatusFolder < ApplicationRecord
  belongs_to :account
  has_many :campaigns, class_name: 'WhatsappStatusCampaign', foreign_key: :folder_id, inverse_of: :folder, dependent: :nullify

  validates :name, presence: true, length: { maximum: 60 }, uniqueness: { scope: :account_id }
  validates :color, format: { with: WhatsappStatusPost::HEX_COLOR }, allow_blank: true
end

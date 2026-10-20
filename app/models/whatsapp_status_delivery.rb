# == Schema Information
#
# Table name: whatsapp_status_deliveries
#
#  id                      :bigint           not null, primary key
#  error_message           :text
#  inbox_name              :string           not null
#  sent_at                 :datetime
#  status                  :integer          default("pending"), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  inbox_id                :bigint
#  waha_message_id         :string
#  whatsapp_status_post_id :bigint           not null
#
# Indexes
#
#  index_whatsapp_status_deliveries_on_inbox_id                 (inbox_id)
#  index_whatsapp_status_deliveries_on_whatsapp_status_post_id  (whatsapp_status_post_id)
#
# Foreign Keys
#
#  fk_rails_...  (inbox_id => inboxes.id) ON DELETE => nullify
#  fk_rails_...  (whatsapp_status_post_id => whatsapp_status_posts.id) ON DELETE => cascade
#
# Um status publicado numa conexão. O post é o que o operador escreveu; a
# entrega é o que aconteceu em cada número, porque publicar em três conexões
# pode dar certo em duas e falhar na terceira, e a tela precisa dizer qual.
#
# O nome da inbox é copiado na criação: a conexão pode ser removida depois e o
# histórico continua tendo que dizer onde aquele status saiu.
class WhatsappStatusDelivery < ApplicationRecord
  belongs_to :whatsapp_status_post
  belongs_to :inbox, optional: true

  enum status: { pending: 0, sent: 1, failed: 2 }, _prefix: :status

  validates :inbox_name, presence: true
end

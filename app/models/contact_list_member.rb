# == Schema Information
#
# Table name: contact_list_members
#
#  id              :bigint           not null, primary key
#  display_name    :string
#  joined_at       :datetime
#  left_at         :datetime
#  role            :string
#  status          :integer          default("active"), not null
#  wa_id           :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  contact_id      :bigint
#  contact_list_id :bigint           not null
#
# Indexes
#
#  index_contact_list_members_on_contact_id                 (contact_id)
#  index_contact_list_members_on_contact_list_id_and_status  (contact_list_id,status)
#  index_contact_list_members_on_list_and_contact           (contact_list_id,contact_id) UNIQUE WHERE (contact_id IS NOT NULL)
#  index_contact_list_members_on_list_and_wa_id             (contact_list_id,wa_id) UNIQUE WHERE (wa_id IS NOT NULL)
#
# Um membro sem `contact` é um participante de grupo que só veio com @lid e a
# WAHA não soube dizer o número: aparece na lista como "sem telefone" e nunca
# entra em disparo. `wa_id` é o id do WhatsApp (…@c.us ou …@lid), só nas
# listas de grupo.
class ContactListMember < ApplicationRecord
  belongs_to :contact_list
  belongs_to :contact, optional: true

  # left — saiu do grupo na última atualização; fica visível, fora do disparo.
  enum status: { active: 0, left: 1 }, _prefix: :status

  validates :contact_id, uniqueness: { scope: :contact_list_id }, allow_nil: true
  validates :wa_id, uniqueness: { scope: :contact_list_id }, allow_nil: true
end

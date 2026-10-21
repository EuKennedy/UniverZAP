# == Schema Information
#
# Table name: contact_lists
#
#  id               :bigint           not null, primary key
#  description      :text
#  group_identifier :string
#  last_error       :string
#  members_count    :integer          default(0), not null
#  metadata         :jsonb            not null
#  name             :string           not null
#  refreshed_at     :datetime
#  source           :string           default("manual"), not null
#  status           :string           default("ready"), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  inbox_id         :bigint
#
# Indexes
#
#  index_contact_lists_on_account_id                       (account_id)
#  index_contact_lists_on_account_id_and_group_identifier  (account_id,group_identifier)
#
# Lista de distribuição: uma FOTO de contatos que vira público de disparo
# (Broadcasts::AudienceResolver, chave `contact_list_ids`). Não se atualiza
# sozinha; a de grupo tem "Atualizar a partir do grupo", que marca quem entrou
# e quem saiu (ContactLists::GroupExtractionService).
#
# Para adicionar/remover contatos de fora daqui (ex.: um bloco do Chatflow),
# use ContactLists::MemberService.
class ContactList < ApplicationRecord
  SOURCES = %w[group csv manual filter].freeze
  STATUSES = %w[ready importing failed].freeze

  belongs_to :account
  belongs_to :inbox, optional: true
  has_many :members, class_name: 'ContactListMember', dependent: :delete_all
  has_many :contacts, through: :members

  validates :name, presence: true, length: { maximum: 120 }
  validates :source, inclusion: { in: SOURCES }
  validates :status, inclusion: { in: STATUSES }
  validates :group_identifier, presence: true, if: -> { source == 'group' }

  scope :from_group, ->(identifier) { where(source: 'group', group_identifier: identifier) }

  def group?
    source == 'group'
  end

  def importing?
    status == 'importing'
  end

  def recount!
    update!(members_count: members.status_active.count)
  end

  # Quem de fato pode receber: membro ativo, com contato e telefone. O
  # consentimento é decidido depois, no AudienceResolver.
  def sendable_contact_ids
    members.status_active.joins(:contact).where.not(contacts: { phone_number: [nil, ''] }).pluck(:contact_id)
  end
end

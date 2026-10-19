# == Schema Information
#
# Table name: whatsapp_flows
#
#  id                :bigint           not null, primary key
#  category          :string           default("OTHER"), not null
#  field_mappings    :jsonb            not null
#  flow_json         :jsonb            not null
#  name              :string(255)      not null
#  preview_url       :string
#  published_at      :datetime
#  status            :string           default("draft"), not null
#  template_key      :string
#  validation_errors :jsonb            not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  inbox_id          :bigint           not null
#  meta_flow_id      :string
#
# Indexes
#
#  index_whatsapp_flows_on_account_id    (account_id)
#  index_whatsapp_flows_on_inbox_id      (inbox_id)
#  index_whatsapp_flows_on_meta_flow_id  (meta_flow_id) UNIQUE WHERE (meta_flow_id IS NOT NULL)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (inbox_id => inboxes.id) ON DELETE => cascade
#

# Um formulário nativo do WhatsApp (Meta "Flow") de uma caixa Cloud API.
#
# O Flow JSON vive AQUI, no nosso banco: a Meta guarda a cópia publicada, e o
# que ela guarda não se edita (publicado só se deprecia). Por isso editar um
# publicado é recusado no modelo — o caminho é duplicar em rascunho novo,
# publicar o novo e depreciar o antigo.
#
# `status` espelha o ciclo de vida da Meta: draft, published, deprecated,
# blocked (endpoint doente) e throttled (10 envios por hora até sarar).
class WhatsappFlow < ApplicationRecord
  CATEGORIES = %w[SIGN_UP SIGN_IN APPOINTMENT_BOOKING LEAD_GENERATION CONTACT_US CUSTOMER_SUPPORT SURVEY OTHER].freeze
  STATUSES = %w[draft published deprecated blocked throttled].freeze
  SENDABLE_STATUSES = %w[published throttled].freeze

  belongs_to :account
  belongs_to :inbox

  validates :name, presence: true, length: { maximum: 255 }
  validates :category, inclusion: { in: CATEGORIES }
  validates :status, inclusion: { in: STATUSES }
  validate :flow_json_has_screens
  validate :inbox_belongs_to_account
  validate :published_json_is_frozen, on: :update

  scope :sendable, -> { where(status: SENDABLE_STATUSES) }

  def draft?
    status == 'draft'
  end

  def published?
    status == 'published'
  end

  def sendable?
    SENDABLE_STATUSES.include?(status)
  end

  # Mode que a Meta espera no envio: rascunho sai como `draft` (só para teste),
  # o resto como `published`.
  def send_mode
    draft? ? 'draft' : 'published'
  end

  # Nome visível de cada campo de entrada, lido do próprio Flow JSON: é a
  # única fonte que não desatualiza quando o operador troca o rótulo. Só
  # componentes com `label` entram — o contêiner Form tem nome, mas não é campo.
  def field_labels
    labels = {}
    each_component(flow_json['screens']) do |component|
      next if component['name'].blank? || component['label'].blank?

      labels[component['name']] = component['label']
    end
    labels
  end

  # Título de cada opção por campo (id → título), para a resposta mostrar
  # "Corte" em vez de "corte".
  def field_options
    options = {}
    each_component(flow_json['screens']) do |component|
      next if component['name'].blank? || !component['data-source'].is_a?(Array)

      options[component['name']] = component['data-source'].to_h { |item| [item['id'].to_s, item['title'].to_s] }
    end
    options
  end

  private

  def each_component(screens, &)
    Array(screens).each do |screen|
      walk(Array(screen.dig('layout', 'children')), &)
    end
  end

  def walk(children, &)
    children.each do |component|
      next unless component.is_a?(Hash)

      yield component
      walk(Array(component['children']), &)
      walk(Array(component['then']), &)
      walk(Array(component['else']), &)
    end
  end

  def flow_json_has_screens
    return if flow_json.is_a?(Hash) && flow_json['screens'].is_a?(Array) && flow_json['screens'].any?

    errors.add(:flow_json, 'must contain at least one screen')
  end

  def inbox_belongs_to_account
    return if inbox.blank? || account.blank?
    return if inbox.account_id == account_id

    errors.add(:inbox, 'must belong to the same account')
  end

  # A Meta não aceita edição de Flow publicado, e deixar o nosso JSON divergir
  # do dela é a forma mais silenciosa de mandar um formulário diferente do que
  # o operador vê na tela.
  def published_json_is_frozen
    return unless flow_json_changed?
    return if status_was == 'draft'

    errors.add(:flow_json, 'cannot change after publishing; duplicate the flow instead')
  end
end

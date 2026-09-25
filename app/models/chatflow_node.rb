# == Schema Information
#
# Table name: chatflow_nodes
#
#  id          :bigint           not null, primary key
#  chatflow_id :bigint           not null
#  account_id  :bigint           not null
#  kind        :integer          default(0), not null
#  name        :string
#  position_x  :float            default(0.0), not null
#  position_y  :float            default(0.0), not null
#  config      :jsonb            default({}), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
class ChatflowNode < ApplicationRecord
  belongs_to :chatflow, inverse_of: :nodes
  belongs_to :account

  has_many :outgoing_edges, class_name: 'ChatflowEdge', foreign_key: :source_node_id,
                            dependent: :destroy, inverse_of: :source_node
  has_many :incoming_edges, class_name: 'ChatflowEdge', foreign_key: :target_node_id,
                            dependent: :destroy, inverse_of: :target_node

  # send_message — text, optionally with one media attachment (media + caption).
  # send_audio   — single audio attachment (voice note).
  # send_media   — single image/video/document attachment.
  # menu         — SAC prompt with selectable options; each option is an
  #                output handle that connects to the next node.
  # set_label    — categorize the contact/conversation (apply labels).
  # end_flow     — terminal node; closes the execution (optional human/AI handoff).
  # confirmation — fecha o atendimento perguntando se resolveu. Duas saídas, cada
  #                uma casada por uma LISTA de palavras-chave, e uma mensagem
  #                própria para quando a resposta não casa com nenhuma.
  enum kind: {
    send_message: 0,
    send_audio: 1,
    send_media: 2,
    menu: 3,
    set_label: 4,
    end_flow: 5,
    assign_agent: 6,
    add_to_kanban: 7,
    webhook: 8,
    confirmation: 9
  }, _prefix: :kind

  validates :name, length: { maximum: 255 }, allow_blank: true

  # Menu options: [{ 'label' => 'Compras', 'value' => '1' }, ...]. The `value`
  # doubles as the edge `source_handle` so each option routes independently.
  def menu_options
    return [] unless kind_menu?

    Array(config['options']).map do |opt|
      { 'label' => opt['label'].to_s, 'value' => opt['value'].to_s }
    end
  end

  # Os dois handles da Confirmação. Fixos e não configuráveis: a etapa tem
  # exatamente dois destinos, e deixar o operador renomeá-los quebraria a ligação
  # já desenhada no canvas no dia em que ele trocasse uma letra.
  RESOLVED = 'resolved'.freeze
  UNRESOLVED = 'unresolved'.freeze

  # Quantas vezes reperguntar antes de desistir. O menu repergunta para SEMPRE,
  # e numa etapa de fechamento isso prende o cliente num robô: quem escreveu um
  # desabafo em vez de "sim" recebe a mesma pergunta até o fim dos tempos.
  MAX_CONFIRMATION_RETRIES = 2

  # Palavras-chave de um dos ramos, normalizadas como o gatilho normaliza as
  # dele: minúsculas, sem espaço nas pontas, sem vazias.
  def confirmation_keywords(handle)
    key = handle == UNRESOLVED ? 'unresolved_keywords' : 'resolved_keywords'
    Array(config[key]).map { |word| word.to_s.downcase.strip }.reject(&:blank?)
  end

  # O que o bot diz quando a resposta não casou. Em branco, ele repergunta sem
  # dizer nada — o que é pior, porque o cliente não descobre o que se espera dele.
  def confirmation_fallback_text
    config['fallback_text'].to_s
  end
end

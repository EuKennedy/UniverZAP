# == Schema Information
#
# Table name: chatflow_executions
#
#  id              :bigint           not null, primary key
#  account_id      :bigint           not null
#  chatflow_id     :bigint           not null
#  conversation_id :bigint           not null
#  current_node_id :bigint
#  status          :integer          default(0), not null
#  context         :jsonb            default({}), not null
#  resume_at       :datetime
#  visited_node_ids :bigint          default([]), not null, is an Array
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
class ChatflowExecution < ApplicationRecord
  belongs_to :account
  belongs_to :chatflow, inverse_of: :executions
  belongs_to :conversation
  belongs_to :current_node, class_name: 'ChatflowNode', optional: true

  # active        — engine is walking the graph (auto-advancing nodes).
  # waiting_input — paused on a menu node, awaiting the customer's reply.
  # completed     — reached an end node / ran out of edges.
  # aborted       — operator took over or the flow was archived mid-run.
  # paused        — um atendente assumiu; fica parada na etapa até alguém
  #                 clicar em "Retomar robô". Fora do índice único de execução
  #                 viva (status < 2), por isso o motor confere à parte.
  enum status: { active: 0, waiting_input: 1, completed: 2, aborted: 3, paused: 4 }, _prefix: :status

  scope :live, -> { where(status: [statuses[:active], statuses[:waiting_input]]) }
  scope :due, -> { status_waiting_input.where(resume_at: ..Time.current) }

  # Marca a passagem por uma etapa. Só a primeira vez: um laço no desenho não
  # pode inflar o funil daquela etapa.
  def visit!(node)
    return if visited_node_ids.include?(node.id)

    update!(visited_node_ids: visited_node_ids + [node.id])
  end

  # Tira a execução da espera do relógio. O update condicional é a trava entre
  # o timer e a resposta do cliente: só um dos dois consegue soltar a etapa.
  def claim_timer!
    self.class.where(id: id).where.not(resume_at: nil)
        .update_all(resume_at: nil, status: self.class.statuses[:active], updated_at: Time.current) == 1 # rubocop:disable Rails/SkipsModelValidations
  end

  def live?
    status_active? || status_waiting_input?
  end
end

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
  enum status: { active: 0, waiting_input: 1, completed: 2, aborted: 3 }, _prefix: :status

  scope :live, -> { where(status: [statuses[:active], statuses[:waiting_input]]) }

  def live?
    status_active? || status_waiting_input?
  end
end

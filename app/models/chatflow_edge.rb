# == Schema Information
#
# Table name: chatflow_edges
#
#  id             :bigint           not null, primary key
#  chatflow_id    :bigint           not null
#  account_id     :bigint           not null
#  source_node_id :bigint           not null
#  target_node_id :bigint           not null
#  source_handle  :string           default("default"), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
class ChatflowEdge < ApplicationRecord
  belongs_to :chatflow, inverse_of: :edges
  belongs_to :account
  belongs_to :source_node, class_name: 'ChatflowNode', inverse_of: :outgoing_edges
  belongs_to :target_node, class_name: 'ChatflowNode', inverse_of: :incoming_edges

  validates :source_handle, presence: true, length: { maximum: 255 },
                            uniqueness: { scope: :source_node_id }
  validate :nodes_share_chatflow

  private

  def nodes_share_chatflow
    return if source_node.blank? || target_node.blank?
    return if source_node.chatflow_id == chatflow_id && target_node.chatflow_id == chatflow_id

    errors.add(:base, 'source and target nodes must belong to the same chatflow')
  end
end

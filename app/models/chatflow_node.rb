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
  enum kind: {
    send_message: 0,
    send_audio: 1,
    send_media: 2,
    menu: 3,
    set_label: 4,
    end_flow: 5
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
end

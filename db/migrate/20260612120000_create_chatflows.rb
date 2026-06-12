class CreateChatflows < ActiveRecord::Migration[7.1]
  def change
    create_chatflows_table
    create_chatflow_nodes_table
    create_chatflow_edges_table
    create_chatflow_executions_table
  end

  private

  def create_chatflows_table
    create_table :chatflows do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :inbox, null: true, foreign_key: { on_delete: :cascade }, index: true
      t.string :name, null: false, limit: 255
      t.text :description
      t.integer :status, null: false, default: 0
      t.integer :trigger_type, null: false, default: 0
      t.jsonb :trigger_config, null: false, default: {}
      t.bigint :start_node_id
      t.bigint :display_id
      t.timestamps
    end
    add_index :chatflows, %i[account_id status]
    add_index :chatflows, %i[account_id display_id], unique: true, where: 'display_id IS NOT NULL'
  end

  def create_chatflow_nodes_table
    create_table :chatflow_nodes do |t|
      t.references :chatflow, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.references :account, null: false, foreign_key: true, index: true
      t.integer :kind, null: false, default: 0
      t.string :name, limit: 255
      t.float :position_x, null: false, default: 0
      t.float :position_y, null: false, default: 0
      t.jsonb :config, null: false, default: {}
      t.timestamps
    end
  end

  def create_chatflow_edges_table
    create_table :chatflow_edges do |t|
      t.references :chatflow, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.references :account, null: false, foreign_key: true, index: true
      t.references :source_node, null: false,
                                 foreign_key: { to_table: :chatflow_nodes, on_delete: :cascade },
                                 index: { name: 'idx_chatflow_edges_on_source_node' }
      t.references :target_node, null: false,
                                 foreign_key: { to_table: :chatflow_nodes, on_delete: :cascade },
                                 index: { name: 'idx_chatflow_edges_on_target_node' }
      t.string :source_handle, null: false, default: 'default', limit: 255
      t.timestamps
    end
    add_index :chatflow_edges, %i[source_node_id source_handle], unique: true, name: 'idx_chatflow_edges_unique_handle'
  end

  def create_chatflow_executions_table
    create_table :chatflow_executions do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :chatflow, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.bigint :current_node_id
      t.integer :status, null: false, default: 0
      t.jsonb :context, null: false, default: {}
      t.timestamps
    end
    # At most one live (active/waiting) execution per conversation.
    add_index :chatflow_executions, :conversation_id, unique: true,
                                                      where: 'status < 2',
                                                      name: 'idx_chatflow_exec_one_live_per_conversation'
  end
end

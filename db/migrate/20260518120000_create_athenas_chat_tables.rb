class CreateAthenasChatTables < ActiveRecord::Migration[7.1]
  CONTENT_LIMIT = 32_000

  def change
    create_chat_threads_table
    create_chat_messages_table
  end

  private

  def create_chat_threads_table
    create_table :ai_chat_threads do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :user, null: false, foreign_key: true, index: true
      t.references :ai_assistant, null: false, foreign_key: { to_table: :ai_assistants }, index: true
      t.bigint :conversation_id, index: true
      t.string :title, null: false, limit: 180
      t.datetime :last_activity_at, null: false
      t.datetime :archived_at
      t.timestamps
    end
    add_index :ai_chat_threads, %i[account_id user_id last_activity_at], name: 'index_ai_chat_threads_on_account_user_activity'
    add_index :ai_chat_threads, %i[conversation_id user_id], where: 'conversation_id IS NOT NULL',
                                name: 'index_ai_chat_threads_on_conversation_user'
  end

  def create_chat_messages_table
    create_table :ai_chat_messages do |t|
      t.references :ai_chat_thread, null: false, foreign_key: { to_table: :ai_chat_threads }, index: true
      t.references :account, null: false, foreign_key: true, index: true
      t.string :role, null: false, limit: 20
      t.text :content, null: false, limit: CONTENT_LIMIT
      t.integer :input_tokens, default: 0
      t.integer :output_tokens, default: 0
      t.float :cost_usd, default: 0.0
      t.string :model
      t.timestamps
    end
    add_index :ai_chat_messages, %i[ai_chat_thread_id created_at], name: 'index_ai_chat_messages_on_thread_created'
  end
end

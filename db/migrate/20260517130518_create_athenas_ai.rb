class CreateAthenasAi < ActiveRecord::Migration[7.1]
  def change
    create_assistants_table
    create_trainings_table
    create_intents_table
    create_invocations_table
    create_link_columns
  end

  private

  def create_assistants_table
    create_table :ai_assistants do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.string :name, null: false, limit: 80
      t.string :role, default: 'Assistente', limit: 60
      t.text :description
      t.string :avatar_url
      t.string :tone, default: 'friendly', limit: 40
      t.string :provider, null: false, default: 'anthropic'
      t.string :model, null: false, default: 'claude-sonnet-4-5'
      t.text :system_prompt
      t.float :temperature, null: false, default: 0.3
      t.integer :max_tokens, null: false, default: 1024
      t.boolean :autopilot_enabled, null: false, default: false
      t.string :encrypted_anthropic_key
      t.string :encrypted_openai_key
      t.jsonb :router_config, null: false, default: { enabled: false, eco: 'claude-haiku-4-5', mid: 'claude-sonnet-4-5', pro: 'claude-opus-4-5' }
      t.jsonb :guardrails, null: false, default: { stop_words: %w[humano atendente], max_messages_per_minute: 4, business_hours: nil }
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :ai_assistants, %i[account_id active]
    add_index :ai_assistants, %i[account_id name], unique: true
  end

  def create_trainings_table
    create_table :ai_trainings do |t|
      t.references :ai_assistant, null: false, foreign_key: true, index: true
      t.references :account, null: false, foreign_key: true, index: true
      t.string :title, null: false, limit: 180
      t.string :source_type, null: false # text, url, file, faq
      t.string :category, default: 'base', limit: 40 # base, catalog, policies, sales, faq
      t.text :content
      t.integer :char_count, default: 0
      t.string :status, default: 'pending', limit: 20 # pending, processing, ready, error
      t.text :error_message
      t.timestamps
    end
    add_index :ai_trainings, %i[ai_assistant_id status]
    add_index :ai_trainings, %i[ai_assistant_id category status]
  end

  def create_intents_table
    create_table :ai_intents do |t|
      t.references :ai_assistant, null: false, foreign_key: true, index: true
      t.references :account, null: false, foreign_key: true, index: true
      t.string :name, null: false, limit: 80
      t.string :triggers # comma-separated keywords
      t.string :action, null: false # auto_reply, route_to_team, create_kanban_task, etc
      t.jsonb :action_payload, null: false, default: {}
      t.boolean :active, null: false, default: true
      t.integer :position, default: 0
      t.timestamps
    end
    add_index :ai_intents, %i[ai_assistant_id active position]
  end

  def create_invocations_table
    create_table :ai_invocations do |t|
      t.references :ai_assistant, null: false, foreign_key: true, index: true
      t.references :account, null: false, foreign_key: true, index: true
      t.bigint :conversation_id
      t.bigint :message_id
      t.string :phase, null: false, default: 'main' # main, classifier, router, summary, suggest
      t.string :model, null: false
      t.integer :input_tokens, default: 0
      t.integer :output_tokens, default: 0
      t.integer :cache_read_tokens, default: 0
      t.integer :cache_write_tokens, default: 0
      t.float :cost_usd, default: 0.0
      t.integer :duration_ms, default: 0
      t.string :status, default: 'success' # success, error
      t.text :error_message
      t.timestamps
    end
    add_index :ai_invocations, %i[ai_assistant_id created_at]
    add_index :ai_invocations, %i[account_id created_at]
    add_index :ai_invocations, %i[phase model created_at]
    add_index :ai_invocations, :conversation_id
  end

  def create_link_columns
    add_reference :inboxes, :ai_assistant, foreign_key: { to_table: :ai_assistants }, null: true
    add_column :inboxes, :ai_mode, :string, default: 'off' # off, suggest, autopilot
    add_reference :conversations, :ai_assistant, foreign_key: { to_table: :ai_assistants }, null: true
    add_column :conversations, :ai_mode, :string # null = inherit from inbox; else override
    add_index :conversations, :ai_mode
  end
end

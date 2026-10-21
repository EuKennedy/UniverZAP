class CreateScheduledMessages < ActiveRecord::Migration[7.1]
  def change
    create_message_sequences
    create_scheduled_messages
    add_column :broadcast_recipients, :message_id, :bigint
    add_column :broadcast_recipients, :replied_at, :datetime
    add_column :broadcast_recipients, :send_after, :datetime
    add_column :broadcast_recipients, :skip_reason, :string
    add_column :broadcasts, :pause_reason, :string
  end

  private

  def create_message_sequences
    create_table :message_sequences do |t|
      t.references :account, null: false, index: true
      t.references :inbox, index: true
      t.string :name, null: false
      t.string :trigger, null: false, default: 'appointment'
      t.boolean :enabled, null: false, default: false
      t.jsonb :steps, null: false, default: []
      t.timestamps
    end
  end

  def create_scheduled_messages
    create_table :scheduled_messages do |t|
      t.references :account, null: false, index: true
      t.references :inbox, null: false, index: true
      t.references :conversation, null: false, index: true
      t.references :contact, null: false, index: true
      t.references :created_by, index: true
      t.references :message_sequence, index: true
      t.integer :sequence_step
      t.text :content, null: false
      t.integer :status, null: false, default: 0
      t.datetime :send_at, null: false
      t.datetime :sent_at
      t.bigint :message_id
      t.boolean :cancel_if_reply, null: false, default: true
      t.boolean :respect_window, null: false, default: false
      t.string :cancel_reason, :error
      t.timestamps
      t.index [:status, :send_at]
    end
  end
end

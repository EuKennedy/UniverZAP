class CreateWhatsappStatusPosts < ActiveRecord::Migration[7.1]
  def change
    create_posts
    create_deliveries
    create_templates
  end

  private

  def create_posts
    create_table :whatsapp_status_posts do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :kind, null: false, default: 'text'
      t.text :body
      t.string :background_color
      t.integer :font, null: false, default: 0
      t.integer :status, null: false, default: 0
      t.jsonb :inbox_ids, null: false, default: []
      t.datetime :scheduled_at
      t.datetime :published_at
      t.timestamps
    end
    add_index :whatsapp_status_posts, [:account_id, :status, :scheduled_at]
  end

  def create_deliveries
    create_table :whatsapp_status_deliveries do |t|
      t.references :whatsapp_status_post, null: false, foreign_key: { on_delete: :cascade }
      t.references :inbox, foreign_key: { on_delete: :nullify }
      t.string :inbox_name, null: false
      t.integer :status, null: false, default: 0
      t.string :waha_message_id
      t.text :error_message
      t.datetime :sent_at
      t.timestamps
    end
  end

  def create_templates
    create_table :whatsapp_status_templates do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.text :body, null: false
      t.string :background_color
      t.integer :font, null: false, default: 0
      t.timestamps
    end
    add_index :whatsapp_status_templates, [:account_id, :name], unique: true
  end
end

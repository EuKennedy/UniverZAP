class CreateWhatsappStatusCampaigns < ActiveRecord::Migration[7.1]
  def change
    create_folders
    create_campaigns
    create_steps
    link_posts
  end

  private

  def create_folders
    create_table :whatsapp_status_folders do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.string :color
      t.timestamps
    end
    add_index :whatsapp_status_folders, [:account_id, :name], unique: true
  end

  def create_campaigns
    create_table :whatsapp_status_campaigns do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :folder, foreign_key: { to_table: :whatsapp_status_folders, on_delete: :nullify }
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :name, null: false
      t.text :description
      t.string :color
      t.integer :status, null: false, default: 0
      t.jsonb :inbox_ids, null: false, default: []
      t.date :starts_on
      t.date :ends_on
      t.integer :cycle_days, null: false, default: 0
      t.string :time_zone, null: false, default: 'America/Sao_Paulo'
      t.timestamps
    end
    add_index :whatsapp_status_campaigns, [:account_id, :status]
  end

  def create_steps
    create_table :whatsapp_status_campaign_steps do |t|
      t.references :campaign, null: false, foreign_key: { to_table: :whatsapp_status_campaigns, on_delete: :cascade }
      t.integer :position, null: false, default: 0
      t.integer :day_offset, null: false, default: 0
      t.string :time_of_day, null: false, default: '09:00'
      t.string :kind, null: false, default: 'text'
      t.text :body
      t.string :background_color
      t.integer :font, null: false, default: 0
      t.integer :repost_count, null: false, default: 0
      t.integer :repost_interval_hours, null: false, default: 24
      t.timestamps
    end
  end

  def link_posts
    add_reference :whatsapp_status_posts, :campaign, foreign_key: { to_table: :whatsapp_status_campaigns, on_delete: :nullify }
    add_reference :whatsapp_status_posts, :campaign_step, foreign_key: { to_table: :whatsapp_status_campaign_steps, on_delete: :nullify }
    add_column :whatsapp_status_posts, :occurrence_key, :string
    add_index :whatsapp_status_posts, [:campaign_id, :occurrence_key], unique: true, where: 'occurrence_key IS NOT NULL'
  end
end

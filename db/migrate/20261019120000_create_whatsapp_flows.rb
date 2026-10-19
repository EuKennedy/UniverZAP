class CreateWhatsappFlows < ActiveRecord::Migration[7.1]
  def change
    create_table :whatsapp_flows do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :inbox, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.string :name, null: false, limit: 255
      t.string :category, null: false, default: 'OTHER'
      t.string :template_key
      t.jsonb :flow_json, null: false, default: {}
      t.jsonb :field_mappings, null: false, default: {}
      t.string :meta_flow_id
      t.string :status, null: false, default: 'draft'
      t.jsonb :validation_errors, null: false, default: []
      t.string :preview_url
      t.datetime :published_at
      t.timestamps
    end
    add_index :whatsapp_flows, :meta_flow_id, unique: true, where: 'meta_flow_id IS NOT NULL'
  end
end

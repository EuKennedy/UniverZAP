# Listas de distribuição: uma foto de contatos (de um grupo do WhatsApp, de um
# CSV, escolhidos à mão ou de um filtro) que vira público de disparo.
class CreateContactLists < ActiveRecord::Migration[7.1]
  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
  def change
    create_table :contact_lists do |t|
      t.references :account, null: false, index: true
      t.string :name, null: false
      t.text :description
      t.string :source, null: false, default: 'manual'
      t.references :inbox, index: false
      t.string :group_identifier
      t.integer :members_count, null: false, default: 0
      t.string :status, null: false, default: 'ready'
      t.string :last_error
      t.datetime :refreshed_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :contact_lists, [:account_id, :group_identifier]

    create_table :contact_list_members do |t|
      t.references :contact_list, null: false, index: false
      t.references :contact, index: true
      t.string :wa_id
      t.string :display_name
      t.string :role
      t.integer :status, null: false, default: 0
      t.datetime :joined_at
      t.datetime :left_at
      t.timestamps
    end
    add_index :contact_list_members, [:contact_list_id, :contact_id], unique: true, where: 'contact_id IS NOT NULL',
                                                                      name: 'index_contact_list_members_on_list_and_contact'
    add_index :contact_list_members, [:contact_list_id, :wa_id], unique: true, where: 'wa_id IS NOT NULL',
                                                                 name: 'index_contact_list_members_on_list_and_wa_id'
    add_index :contact_list_members, [:contact_list_id, :status]

    # "Estes contatos nunca falaram com o salão": quem confirmou e quando.
    add_column :broadcasts, :cold_contacts_confirmed_at, :datetime
    add_column :broadcasts, :cold_contacts_confirmed_by_id, :bigint
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize
end

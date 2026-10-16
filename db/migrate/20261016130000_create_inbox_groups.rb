class CreateInboxGroups < ActiveRecord::Migration[7.1]
  # UniverZAP: the groups that organise "Canais" in the sidebar. A group with a
  # `kind` (whatsapp, instagram...) collects every inbox of that kind that was
  # not put somewhere else on purpose; a group without one holds only the
  # inboxes moved into it.
  def change
    create_table :inbox_groups do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.string :name, null: false, limit: 60
      t.string :kind
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :inbox_groups, %i[account_id kind], unique: true, where: 'kind IS NOT NULL'
    add_reference :inboxes, :inbox_group, foreign_key: { on_delete: :nullify }, index: true
  end
end

class CreateAiBelezakiConnections < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_belezaki_connections do |t|
      # Unique: one agenda per agent. Two would put two tools called
      # `consultar_horarios` in the same payload, which the API rejects outright.
      t.references :ai_assistant, null: false, foreign_key: true, index: { unique: true }
      t.references :account, null: false, foreign_key: true, index: false
      # Frozen at connect time rather than resolved per reply. Resolution runs
      # through the ACCOUNT, and an account whose link changes would silently
      # move a live agent onto somebody else's agenda — which has happened once
      # already, see the comment in Ai::Belezaki::TenantResolver.
      t.string :external_id, null: false
      t.string :salon_name
      t.string :timezone, null: false, default: 'America/Sao_Paulo'
      t.string :status, null: false, default: 'active'
      t.datetime :connected_at
      t.text :last_error
      t.datetime :last_error_at
      t.timestamps
    end
  end
end

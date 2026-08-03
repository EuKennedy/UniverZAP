# The generic "Integrações" mechanism: a tenant-configured HTTP tool an agent
# can call mid-conversation. Scoped to ONE agent in ONE workspace and carrying
# that workspace's own endpoint + credentials, so an integration one workspace
# connects is invisible and unusable to every other account. Nothing global,
# nothing hardcoded — univercart is simply the first row a workspace creates.
class CreateAiCustomTools < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_custom_tools do |t|
      t.references :ai_assistant, null: false, foreign_key: true, index: false
      t.references :account, null: false, foreign_key: true, index: false
      t.string :title, null: false
      t.string :slug, null: false
      t.text :description
      t.text :endpoint_url, null: false
      t.string :http_method, null: false, default: 'GET'
      t.string :auth_type, null: false, default: 'none'
      # Per-record credentials (this workspace's own key/token). The isolation
      # boundary: another tenant never sees this row, let alone its secrets.
      t.jsonb :auth_config, null: false, default: {}
      t.jsonb :param_schema, null: false, default: []
      t.text :request_template
      t.text :response_template
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end
    # The executor loads "this agent's enabled tools" — the whole read path.
    add_index :ai_custom_tools, %i[ai_assistant_id enabled]
    # The slug is the LLM function name; unique per agent so two agents can each
    # have a "buscar_produto" without colliding.
    add_index :ai_custom_tools, %i[ai_assistant_id slug], unique: true
  end
end

class WidenAthenasEncryptedColumns < ActiveRecord::Migration[7.1]
  def up
    change_column :ai_assistants, :encrypted_anthropic_key, :text
    change_column :ai_assistants, :encrypted_openai_key, :text
  end

  def down
    change_column :ai_assistants, :encrypted_anthropic_key, :string
    change_column :ai_assistants, :encrypted_openai_key, :string
  end
end

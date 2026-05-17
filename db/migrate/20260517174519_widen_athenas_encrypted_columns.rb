class WidenAthenasEncryptedColumns < ActiveRecord::Migration[7.1]
  def change
    change_column :ai_assistants, :encrypted_anthropic_key, :text
    change_column :ai_assistants, :encrypted_openai_key, :text
  end
end

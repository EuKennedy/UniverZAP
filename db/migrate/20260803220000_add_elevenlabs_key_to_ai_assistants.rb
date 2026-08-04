# Speech-to-text credential, per agent.
#
# Same shape as the Anthropic and OpenAI keys already on this table: the
# workspace may bring its own vendor account, and the platform key in ENV is
# the fallback. Multi-tenant by construction — one workspace's transcription
# never runs on another workspace's credential or bill.
class AddElevenlabsKeyToAiAssistants < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_assistants, :encrypted_elevenlabs_key, :text
  end
end

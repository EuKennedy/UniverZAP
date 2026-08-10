# The name the CUSTOMER sees above the agent's replies on WhatsApp, which is
# not the same thing as `name` — that one is how the operator finds the agent in
# the dashboard ("Elisa 2.0 (teste)"). Null keeps replies unsigned, exactly as
# they have always been sent.
class AddConversationDisplayNameToAiAssistants < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_assistants, :conversation_display_name, :string
  end
end

# Chatflow no nível de automação do BotConversa:
# - resume_at: quando a etapa "Esperar"/"Digitando…" solta o fluxo. Quem solta é
#   o mesmo scanner minuto a minuto das mensagens agendadas.
# - visited_node_ids: por onde a execução passou, em ordem — base do funil por
#   bloco (entraram/avançaram/pararam) sem tabela de eventos nova.
class AddChatflowAutomationToExecutions < ActiveRecord::Migration[7.1]
  def change
    add_column :chatflow_executions, :resume_at, :datetime
    add_column :chatflow_executions, :visited_node_ids, :bigint, array: true, default: [], null: false
    add_index :chatflow_executions, :resume_at, where: 'resume_at IS NOT NULL', name: 'idx_chatflow_exec_resume_at'
  end
end

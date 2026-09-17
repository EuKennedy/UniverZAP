# O agente do wiki mora na mesma tabela dos agentes de atendimento — não existe
# agente global neste produto, tudo é Current.account — mas ele não é um agente
# que a operação gerencia: ninguém edita o prompt dele, ninguém o coloca numa
# inbox, e ele não pode aparecer na lista ao lado da Elisa nem virar o padrão do
# copiloto por ser o primeiro da ordenação.
class AddPurposeToAiAssistants < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_assistants, :purpose, :string, null: false, default: 'attendance'
    add_index :ai_assistants, %i[account_id purpose]
  end
end

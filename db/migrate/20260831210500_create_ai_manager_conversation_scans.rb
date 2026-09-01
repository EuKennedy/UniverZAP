# A rodada do moderador, separada de ai_manager_runs de propósito.
#
# Reusar a tabela do Gerente exigiria afrouxar a validação de `triggered_by` e
# ensinar Overview, AnalysisService e a controller a filtrar um tipo novo, tudo
# isso numa tabela que já está em produção atendendo cliente. O ganho seria uma
# tabela a menos; o risco seria a fila do Gerente passar a contar rodadas de
# moderação como auditoria e anunciar uma "última varredura" que nunca olhou um
# agente. As duas também medem coisas diferentes: esta guarda a janela pedida e
# quantas conversas o modelo LEU, que na do Gerente não existem.
class CreateAiManagerConversationScans < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_manager_conversation_scans do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.bigint :user_id
      t.string :status, null: false, default: 'running'
      # A janela pedida, em horas. Gravada e não derivada, porque o operador
      # pode pedir 24h hoje e 30 dias amanhã, e sem isto ninguém consegue reler
      # depois contra o que a leitura foi tirada.
      t.integer :window_hours, null: false, default: 24
      t.datetime :started_at
      t.datetime :finished_at
      t.integer :conversations_scanned, null: false, default: 0
      t.integer :conversations_read, null: false, default: 0
      t.integer :findings_count, null: false, default: 0
      t.integer :cost_cents_brl, null: false, default: 0
      # Quantas ficaram de fora do teto, o motivo de a leitura ter sido pulada,
      # e o erro quando falhou. A tela mostra tudo isso: uma varredura que corta
      # em silêncio se apresenta como completa.
      t.jsonb :summary, null: false, default: {}
      t.timestamps
    end
    add_index :ai_manager_conversation_scans, %i[account_id created_at]
  end
end

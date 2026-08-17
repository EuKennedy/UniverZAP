# O Gerente: um agente que audita os agentes da conta, aponta o que quebrou com
# evidência, e propõe mudança que só vale depois de um humano aprovar.
#
# Três tabelas e não uma, porque são três tempos de vida diferentes: a rodada é
# um evento (aconteceu, custou, varreu tanto), a sugestão sobrevive à rodada que
# a criou (fica pendente até alguém decidir, e depois guarda o que virou), e o
# liga/desliga de cada verificação é configuração da conta, que não pode morrer
# junto com a rodada da semana passada.
#
# Nada aqui aplica nada sozinho. A sugestão nasce `pending` e as duas únicas
# saídas são um humano aprovar ou dispensar: uma alavanca que se puxa sozinha
# não é auditoria, é outro agente solto em produção.
class CreateAiManagerTables < ActiveRecord::Migration[7.1]
  def change
    create_runs
    create_suggestions
    create_check_settings
  end

  def create_runs
    create_table :ai_manager_runs do |t|
      t.references :account, null: false, foreign_key: true, index: false
      # Quem mandou rodar, quando foi manual. Sem chave estrangeira, igual a
      # ai_prompt_versions.created_by_id: a remoção de usuário nesta base tem
      # máquina própria e não pode esbarrar numa auditoria antiga.
      t.bigint :user_id
      t.string :status, null: false, default: 'running'
      t.string :triggered_by, null: false, default: 'schedule'
      run_measurement_columns(t)
      t.timestamps
    end
    # A leitura é sempre "as últimas rodadas desta conta".
    add_index :ai_manager_runs, %i[account_id created_at]
  end

  def run_measurement_columns(table)
    table.datetime :started_at
    table.datetime :finished_at
    # A janela analisada fica gravada na rodada, e não é derivada de created_at:
    # uma execução manual pode pedir um período que não termina agora, e sem
    # isto ninguém consegue reler depois contra o que a conclusão foi tirada.
    table.datetime :period_start
    table.datetime :period_end
    table.integer :conversations_analysed, null: false, default: 0
    table.integer :cost_cents_brl, null: false, default: 0
    # Contadores e o motivo de uma recusa (`insufficient_data`), para a tela
    # explicar uma rodada que terminou sem sugestão nenhuma em vez de mostrar
    # uma lista vazia que parece defeito.
    table.jsonb :summary, null: false, default: {}
  end

  def create_suggestions
    create_table :ai_manager_suggestions do |t|
      suggestion_ownership_columns(t)
      suggestion_finding_columns(t)
      suggestion_decision_columns(t)
      t.timestamps
    end
    add_suggestion_indexes
  end

  def suggestion_ownership_columns(table)
    table.references :account, null: false, foreign_key: true, index: false
    table.references :ai_assistant, null: false, foreign_key: true, index: false
    table.references :ai_manager_run, null: false, foreign_key: true, index: false
  end

  def suggestion_finding_columns(table)
    table.string :check_key, null: false
    table.string :severity, null: false, default: 'normal'
    table.string :title, null: false
    table.text :rationale
    # { conversation_id, excerpt, metric, value }. A evidência viaja com a
    # sugestão porque a tela precisa mostrar o caso concreto junto do número:
    # "23% das conversas" não convence ninguém a mexer no agente, e a frase que
    # o agente escreveu convence.
    table.jsonb :evidence, null: false, default: {}
    # 'training' (memória) ou 'prompt_version' (candidata na disputa A/B). São
    # as duas únicas alavancas que o Gerente tem.
    table.string :target, null: false
    table.jsonb :proposed, null: false, default: {}
  end

  def suggestion_decision_columns(table)
    table.string :status, null: false, default: 'pending'
    table.datetime :applied_at
    table.string :dismissed_reason
    # O que a aprovação produziu. Nullify em vez de cascade: apagar um documento
    # de treino não pode apagar o registro de que alguém aprovou aquela mudança,
    # pela mesma razão que a entrada do ledger sobrevive à remoção do agente.
    table.references :ai_prompt_version, foreign_key: { on_delete: :nullify }, index: false
    table.references :ai_training, foreign_key: { on_delete: :nullify }, index: false
    # Preenchido depois, medindo se a mudança fez efeito. Vazio até lá, porque
    # uma sugestão aplicada ontem ainda não tem resultado e fingir que tem seria
    # inventar o único número que justifica a feature existir.
    table.jsonb :outcome, null: false, default: {}
  end

  def add_suggestion_indexes
    # A fila da tela: as pendentes da conta, mais recentes primeiro.
    add_index :ai_manager_suggestions, %i[account_id status created_at]
    add_index :ai_manager_suggestions, %i[ai_assistant_id status]
    # Uma sugestão por verificação, por agente, por rodada. O motor já deduplica
    # em Ruby; isto é o que garante que uma verificação nova, escrita por outra
    # pessoa daqui a um ano, não consiga encher a fila com vinte cartões do
    # mesmo problema.
    add_index :ai_manager_suggestions, %i[ai_manager_run_id ai_assistant_id check_key],
              unique: true, name: 'index_ai_manager_suggestions_unique_finding'
    # E uma carta ABERTA por verificação, por agente, atravessando rodadas.
    #
    # O índice de cima só enxerga uma rodada, e a repetição que o operador vê na
    # tela acontece entre rodadas: a varredura semanal e um "rodar agora" que
    # cheguem juntos são duas rodadas diferentes, as duas leem a fila antes de a
    # outra escrever, e as duas criam a mesma carta. O `already_open?` do motor
    # perde essa corrida por ser leitura seguida de escrita; este índice não
    # perde, e Ai::Manager::AnalysisService já trata a violação como "não criar a
    # segunda" em vez de derrubar a rodada.
    #
    # Parcial de propósito: depois de decidida (aplicada ou dispensada), a mesma
    # verificação PRECISA poder abrir outra carta no mês que vem, senão um
    # problema que voltou nunca mais seria apontado.
    add_index :ai_manager_suggestions, %i[account_id ai_assistant_id check_key],
              unique: true, where: "status IN ('pending', 'approved')",
              name: 'index_ai_manager_suggestions_unique_open'
  end

  def create_check_settings
    create_table :ai_manager_check_settings do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.string :check_key, null: false
      # Ligada até alguém desligar. A ausência de linha significa ligada, então
      # uma verificação nova entra em operação sem precisar de backfill.
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end
    add_index :ai_manager_check_settings, %i[account_id check_key], unique: true
  end
end

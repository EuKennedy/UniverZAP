# O moderador de conversas: uma linha por problema encontrado numa conversa.
#
# Tabela própria e não mais um tipo de `ai_manager_suggestions`, porque os dois
# objetos têm prazo de validade oposto. A sugestão do Gerente é sobre um HÁBITO
# do agente ("promete horário sem agendar"), vale por semanas e só morre quando
# alguém decide sobre ela. O achado daqui é sobre uma PESSOA agora ("a Fernanda
# está esperando desde ontem"), e morre no instante em que alguém responde. Na
# mesma fila, o urgente afoga o estrutural e o estrutural polui o urgente com
# cartão que já foi resolvido, e a fila vira um lugar que ninguém abre.
#
# Nada aqui é aprovável, aplicável ou treinável. O achado aponta e some do
# filtro; quem resolve é a pessoa, na conversa, com o clique do cartão.
#
# O índice único é a peça que faz o painel funcionar do jeito que foi pedido: a
# leitura fica GRAVADA e as rodadas seguintes atualizam o mesmo achado em vez de
# empilhar cópias. Sem ele, rodar três vezes no mesmo dia mostraria a mesma
# cliente esperando três vezes, e o filtro por dia passaria a contar duplicata.
class CreateAiManagerConversationFindings < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_manager_conversation_findings do |t|
      ownership_columns(t)
      finding_columns(t)
      timing_columns(t)
      t.timestamps
    end
    add_finding_indexes
  end

  def ownership_columns(table)
    table.references :account, null: false, foreign_key: true, index: false
    # A varredura que viu o achado PELA ÚLTIMA vez, e não a que o criou: o
    # cartão precisa dizer "conferido na leitura de hoje", que é o que separa
    # um problema vivo de um resíduo de duas semanas atrás.
    table.bigint :scan_id
    # Sem chave estrangeira, igual ao resto do log do Athenas: a conversa pode
    # ser apagada por retenção e o achado histórico não pode cair junto. O
    # cartão esconde o botão quando o alvo sumiu, em vez de abrir link quebrado.
    table.bigint :conversation_id, null: false
    # A sequência POR CONTA, que é o que vai na URL /conversations/:display_id.
    # Guardada aqui e não traduzida na leitura porque o clique é a razão de a
    # tela existir, e uma consulta a mais por cartão o tornaria lento à toa.
    table.integer :conversation_display_id
    table.bigint :contact_id
    table.bigint :ai_assistant_id
  end

  def finding_columns(table)
    table.string :case_key, null: false
    table.string :severity, null: false, default: 'medium'
    table.string :title, null: false
    table.text :detail
    # O trecho literal pelo qual o achado existe, quase sempre a última coisa
    # que o cliente escreveu. É o que faz o operador entender o cartão sem abrir
    # a conversa, e é o que impede o painel de virar uma lista de rótulos.
    table.text :excerpt
    # Quem deixou parado: 'agent', 'human' ou 'none' (ninguém respondeu ainda).
    # Coluna e não derivação, porque é o filtro que foi pedido e derivar isso na
    # leitura custaria uma varredura de mensagens por cartão.
    table.string :author, null: false, default: 'none'
    # 'triage' quando saiu de SQL puro e não custou nada, 'reading' quando saiu
    # da leitura por modelo. Fica visível na tela: o operador tem direito de
    # saber qual conclusão foi contada e qual foi interpretada.
    table.string :source, null: false, default: 'triage'
    # Dinheiro parado, quando a conversa tem oportunidade estimada. É o critério
    # de ordenação junto com o tempo: cliente de R$ 900 esperando 30h vem antes
    # de dúvida de R$ 40 esperando 3h, mesmo sendo mais antiga.
    table.integer :value_cents_brl, null: false, default: 0
    table.jsonb :metadata, null: false, default: {}
  end

  def timing_columns(table)
    # QUANDO o problema aconteceu, que é a última coisa que o cliente escreveu.
    # É por esta coluna que o filtro de dias fatia, e não por created_at: uma
    # releitura de hoje sobre uma conversa de terça não pode empurrar aquele
    # caso para dentro do filtro de "últimas 24h".
    table.datetime :occurred_at, null: false
    table.datetime :waiting_since
    table.datetime :last_seen_at, null: false
  end

  def add_finding_indexes
    # A leitura da tela é sempre "os achados desta conta, nesta janela, do mais
    # grave para o mais antigo".
    add_index :ai_manager_conversation_findings, %i[account_id occurred_at],
              name: 'idx_manager_findings_account_occurred'
    add_index :ai_manager_conversation_findings, %i[account_id author occurred_at],
              name: 'idx_manager_findings_account_author'
    add_index :ai_manager_conversation_findings, :conversation_id,
              name: 'idx_manager_findings_conversation'
    # A garantia de que rodar de novo atualiza em vez de duplicar.
    add_index :ai_manager_conversation_findings, %i[account_id conversation_id case_key],
              unique: true, name: 'idx_manager_findings_unique_case'
  end
end

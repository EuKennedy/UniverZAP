# Executa uma sugestão que um humano aprovou, e só isso.
#
# As duas alavancas, inteiras:
#
#   training       — vira um documento na memória do agente, pronto para uso.
#   prompt_version — vira uma candidata em RASCUNHO e entra na disputa A/B que já
#                    existe. Nunca vira live.
#
# Quem promove continua sendo Ai::PromotionPolicy: 20 duelos, 70% de vitória,
# zero perda crítica, teto de custo e de latência. O Gerente coloca o desafiante
# no ringue; ele não decide a luta. Um agente que promove o próprio texto porque
# achou o argumento convincente é exatamente a máquina que este módulo inteiro
# existe para não ser.
class Ai::Manager::Applier
  class UnknownTarget < StandardError; end
  class CrossAccountSuggestion < StandardError; end

  # Quantas respostas antigas entram na disputa quando a candidata nasce. Cada
  # duelo é uma chamada paga, então o lote é o mínimo que serve para alguma
  # coisa — e o mínimo que serve é exatamente o que a política de promoção
  # exige.
  #
  # Derivado, e não um segundo literal, porque já divergiu: o comentário dizia
  # 20 e a constante dizia 10, então toda candidata aprovada parava em 10
  # comparações julgadas e `promotable?` era falsa para sempre. O operador
  # aprovava, lia "a disputa começou", e nada acontecia — sem erro, sem log,
  # sem promoção. A alavanca inteira morria no rascunho.
  REPLAY_BATCH = Ai::PromotionPolicy::MIN_COMPARISONS

  def initialize(suggestion:, user: nil)
    @suggestion = suggestion
    @user = user
  end

  # Idempotente por trava de linha, e não por checagem otimista: dois cliques no
  # botão de aprovar chegam em duas requisições simultâneas, e sem o lock as duas
  # leem `pending` e as duas aplicam, criando dois documentos ou duas candidatas
  # com o mesmo conteúdo.
  #
  # A trava resolve a corrida; quem resolve a repetição é `open?`. Perguntar
  # apenas `applied?` deixava dois caminhos abertos para a segunda aplicação, e
  # nenhum deles é hipotético: uma sugestão DISPENSADA não é `applied`, então um
  # POST repetido em cima dela viraria documento depois de o operador ter dito
  # não; e `inconclusive` é onde uma sugestão já aplicada para quando a medição
  # não conclui nada, então reaprová-la criaria o segundo documento.
  def perform
    version = nil
    Ai::Manager::Suggestion.transaction do
      locked = Ai::Manager::Suggestion.lock.find(@suggestion.id)
      version = apply(locked) if locked.open?
      @suggestion = locked
    end
    # Os duelos são enfileirados DEPOIS do commit. Dentro da transação, o worker
    # sai correndo contra ela, busca a candidata pelo id e não acha nada: a
    # disputa simplesmente não aconteceria, em silêncio.
    queue_duels(version) if version
    @suggestion
  end

  private

  def apply(suggestion)
    guard_account!(suggestion)
    case suggestion.target
    when 'training' then apply_training(suggestion)
    when 'prompt_version' then apply_prompt_version(suggestion)
    else raise UnknownTarget, "alavanca desconhecida: #{suggestion.target.inspect}"
    end
  end

  # Defesa em profundidade. A controller já busca a sugestão dentro da conta, mas
  # este serviço escreve na memória de um agente e no texto que ele fala com
  # cliente, e um id cruzado aqui seria uma conta editando o agente de outra.
  def guard_account!(suggestion)
    return if suggestion.account_id == suggestion.ai_assistant.account_id

    raise CrossAccountSuggestion, "sugestão #{suggestion.id} aponta para agente de outra conta"
  end

  # As duas devolvem a candidata criada, ou nil: é o que diz a `perform` se
  # existe disputa para enfileirar depois do commit.
  #
  # `status: 'ready'` não é detalhe: a recuperação de conhecimento só lê
  # documentos prontos, e a coluna nasce `pending` por padrão. Um documento
  # aprovado que ficasse pendente seria memória que o operador vê na lista e o
  # agente nunca recebe, que é o bug que a tela de treinos já teve.
  def apply_training(suggestion)
    proposed = suggestion.proposed.to_h
    training = Ai::Training.create!(
      account_id: suggestion.account_id, ai_assistant_id: suggestion.ai_assistant_id,
      title: proposed['title'].presence&.truncate(180) || suggestion.title.truncate(180),
      category: category_for(proposed['category']), source_type: 'text',
      status: 'ready', content: proposed['content'].to_s
    )
    settle!(suggestion, training: training)
    nil
  end

  def apply_prompt_version(suggestion)
    assistant = suggestion.ai_assistant
    version = Ai::PromptVersionService.new(assistant: assistant, user: @user)
                                      .create_draft(system_prompt: candidate_prompt(assistant, suggestion))
    settle!(suggestion, version: version)
    version
  end

  # A instrução é ACRESCENTADA ao que o agente já roda, nunca substitui. As
  # instruções que o dono da operação escreveu à mão são a parte do prompt que
  # ninguém mais consegue reescrever, e perdê-las porque uma sugestão automática
  # foi aprovada seria o pior estrago que esta classe conseguiria fazer.
  def candidate_prompt(assistant, suggestion)
    proposed = suggestion.proposed.to_h
    return proposed['system_prompt'] if proposed['system_prompt'].present?

    [assistant.effective_system_prompt.to_s.strip, proposed['instruction'].to_s.strip].reject(&:blank?).join("\n\n")
  end

  # Enfileira os duelos contra respostas reais que o agente já deu. O job já
  # recusa duelo entre contas diferentes e já protege o saldo do cliente, então
  # aqui é só escolher o lote.
  def queue_duels(version)
    version.ai_assistant.invocations.live
           .where.not(ai_response: nil).where.not(user_message: nil)
           .order(created_at: :desc).limit(REPLAY_BATCH).ids
           .each { |invocation_id| Ai::AbReplayJob.perform_later(invocation_id, version.id) }
  end

  def category_for(value)
    Ai::Training::CATEGORIES.include?(value.to_s) ? value.to_s : 'base'
  end

  def settle!(suggestion, training: nil, version: nil)
    suggestion.update!(
      status: 'applied', applied_at: Time.current,
      ai_training: training, ai_prompt_version: version
    )
  end
end

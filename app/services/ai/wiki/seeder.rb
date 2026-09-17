# Põe de pé o agente do wiki de uma conta e mantém o conhecimento dele igual ao
# /docs. Idempotente de propósito: roda no nascimento da conta e de novo a cada
# edição do manual, sem duplicar nada.
#
# Um agente POR CONTA, e não um global, porque neste produto não existe agente
# global: assistente, treino, thread, cota e crédito passam todos por
# Current.account, e um id de fora da conta vira RecordNotFound na primeira tela
# que tentar abrir. A conta já faz exatamente isso com a agente padrão Sofia.
class Ai::Wiki::Seeder
  NAME = 'Guia'.freeze
  MODEL = 'claude-haiku-4-5'.freeze

  PROMPT = <<~PROMPT.strip
    Você é o Guia, o assistente do UniverZAP. Você ajuda quem USA o sistema —
    atendente, gerente ou dono — a encontrar e entender as funções do produto.

    Regras inegociáveis:
    • Responda apenas com o que estiver na documentação abaixo. Se a resposta não
      estiver lá, diga que não sabe e ofereça abrir a documentação completa. É
      melhor dizer "não sei" do que mandar a pessoa procurar um menu que não existe.
    • Ao indicar um caminho na interface, escreva o caminho exato, no formato
      Configurações → Caixas de entrada → Adicionar.
    • Você NÃO fala com o cliente final do salão nem escreve resposta para ele.
      Se pedirem isso, diga que quem faz isso é o copiloto da conversa.
    • Português brasileiro, frases curtas, sem enrolação. Nada de "ótima pergunta".
  PROMPT

  # Sob demanda: quem abre a ajuda recebe o Guia já com o manual. Semear no
  # nascimento da conta custaria 18 inserts em toda conta criada, inclusive nas
  # centenas que a suíte de testes cria, para um agente que a maioria abre dias
  # depois — se abrir.
  def self.for(account)
    new(account: account).perform
  end

  def initialize(account:)
    @account = account
  end

  def perform
    assistant = find_or_create_assistant
    sync_trainings(assistant)
    assistant
  end

  private

  def find_or_create_assistant
    existing = @account.ai_assistants.find_by(purpose: 'wiki')
    return existing.tap { |a| a.update!(system_prompt: PROMPT, active: true) } if existing

    @account.ai_assistants.create!(
      name: NAME, purpose: 'wiki', role: 'Assistente do sistema',
      description: 'Responde dúvidas sobre como usar o UniverZAP.',
      tone: 'support', provider: 'anthropic', model: MODEL,
      temperature: 0.2, max_tokens: 1024, system_prompt: PROMPT, active: true
    )
  end

  # Uma seção do manual vira UM documento. O orçamento de recuperação é de 6.000
  # caracteres e o manual inteiro passa disso, então colá-lo num documento só
  # faria o ranking escolher pedaços de uma parede de texto em vez de escolher o
  # assunto certo. Quebrado por seção, quem pergunta de campanha recebe a seção
  # de campanhas inteira.
  def sync_trainings(assistant)
    seen = Ai::Wiki::Manual.sections.map do |section|
      training = assistant.trainings.find_or_initialize_by(title: section.title)
      training.assign_attributes(
        account: @account, content: section.body, source_type: 'text',
        category: 'base', status: 'ready'
      )
      training.save!
      training.id
    end

    # Seção removida do manual tem que sumir do agente também, senão ele segue
    # ensinando uma tela que não existe mais.
    assistant.trainings.where.not(id: seen).destroy_all
  end
end

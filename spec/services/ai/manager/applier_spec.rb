# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Manager::Applier do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account, system_prompt: 'Você atende o salão da Ana.') }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  # `*traits` e não `**attrs`: chamado como `suggestion(:training)`, uma
  # assinatura só de argumentos nomeados recebe o símbolo como posicional e
  # estoura em "wrong number of arguments (given 1, expected 0)" antes de a
  # primeira asserção do arquivo rodar.
  def suggestion(*traits)
    create(:ai_manager_suggestion, *traits, ai_assistant: assistant)
  end

  def apply(record)
    described_class.new(suggestion: record, user: administrator).perform
  end

  describe 'a alavanca de memória' do
    let(:record) { suggestion(:training) }

    it 'vira um documento na memória do agente' do
      expect { apply(record) }.to change(Ai::Training, :count).by(1)

      training = Ai::Training.last
      expect(training.ai_assistant_id).to eq(assistant.id)
      expect(training.category).to eq('sales')
      expect(training.title).to eq('Como responder pergunta de preço')
    end

    # A recuperação de conhecimento só lê documento pronto, e a coluna nasce
    # pendente. Um documento aprovado que ficasse pendente seria memória que o
    # operador vê na lista e o agente nunca recebe.
    it 'nasce pronto, senão o agente nunca leria' do
      apply(record)

      expect(Ai::Training.last.status).to eq('ready')
    end

    it 'liga a sugestão ao que ela produziu' do
      applied = apply(record)

      expect(applied.status).to eq('applied')
      expect(applied.applied_at).to be_present
      expect(applied.ai_training_id).to eq(Ai::Training.last.id)
    end

    it 'cai numa categoria conhecida quando a proposta traz uma inválida' do
      record.update!(proposed: record.proposed.merge('category' => 'inventada'))
      apply(record)

      expect(Ai::Training.last.category).to eq('base')
    end
  end

  describe 'a alavanca de instrução' do
    let(:record) { suggestion }

    it 'vira uma candidata em rascunho' do
      expect { apply(record) }.to change(Ai::PromptVersion, :count).by(1)

      expect(Ai::PromptVersion.last.status).to eq('draft')
    end

    # O ponto inteiro da feature. Quem promove é Ai::PromotionPolicy, com 20
    # duelos, 70% de vitória e zero perda crítica. O Gerente coloca o desafiante
    # no ringue; ele não decide a luta.
    it 'NUNCA promove sozinha' do
      apply(record)

      expect(assistant.reload.live_prompt_version).to be_nil
      expect(Ai::PromptVersion.live.count).to be_zero
    end

    it 'acrescenta a instrução ao prompt que o agente já roda, sem substituir' do
      apply(record)

      prompt = Ai::PromptVersion.last.system_prompt
      expect(prompt).to include('Você atende o salão da Ana.')
      # A instrução INTEIRA, e não um pedaço dela: comparar substring escrita à
      # mão fez este teste reprovar por uma letra maiúscula quando a cópia da
      # sugestão foi reescrita, sem que nada do comportamento tivesse mudado.
      expect(prompt).to include(record.proposed['instruction'])
    end

    it 'coloca a candidata na disputa A/B que já existe' do
      create(:ai_invocation, account: account, ai_assistant: assistant, message_id: 1, conversation_id: 1,
                             user_message: 'quanto custa?', ai_response: 'Fica R$ 200.')

      expect { apply(record) }.to have_enqueued_job(Ai::AbReplayJob)
    end

    it 'liga a sugestão à candidata que ela produziu' do
      applied = apply(record)

      expect(applied.status).to eq('applied')
      expect(applied.ai_prompt_version_id).to eq(Ai::PromptVersion.last.id)
    end
  end

  # Dois cliques no botão chegam em duas requisições, e sem a trava as duas leem
  # `pending` e as duas aplicam.
  describe 'aprovar duas vezes' do
    it 'não cria dois documentos' do
      record = suggestion(:training)
      apply(record)

      expect { apply(record) }.not_to change(Ai::Training, :count)
    end

    it 'não cria duas candidatas' do
      record = suggestion
      apply(record)

      expect { apply(record) }.not_to change(Ai::PromptVersion, :count)
    end
  end

  # Defesa em profundidade: este serviço escreve na memória de um agente e no
  # texto que ele fala com cliente, então um id cruzado aqui seria uma conta
  # editando o agente de outra.
  it 'recusa aplicar uma sugestão que aponta para o agente de outra conta' do
    stranger = create(:ai_assistant, account: create(:account))
    crossed = create(:ai_manager_suggestion, ai_assistant: stranger, account: account,
                                             ai_manager_run: create(:ai_manager_run, account: account))

    expect { apply(crossed) }.to raise_error(described_class::CrossAccountSuggestion)
    expect(crossed.reload.status).to eq('pending')
  end

  it 'recusa uma alavanca que não existe' do
    record = suggestion
    # rubocop:disable Rails/SkipsModelValidations
    record.update_column(:target, 'ferramenta')
    # rubocop:enable Rails/SkipsModelValidations

    expect { apply(record) }.to raise_error(described_class::UnknownTarget)
  end
end

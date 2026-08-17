# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Manager::Checks::LoosePromise do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:ids) { (1..10_000).each }
  # Uma frase que Ai::Guardrails::ResponseAudit::LOOSE_PROMISE realmente casa,
  # e em mais de uma frase de propósito.
  #
  # A verificação recorta o trecho com essa mesma regex e, quando nada casa,
  # `sentence_containing` devolve a resposta inteira. Com um texto de uma frase
  # só, ou com uma frase que a regex ignora, o teste do trecho passaria mesmo
  # que o recorte nunca tivesse acontecido: seria cobertura de mentira em cima
  # justamente do pedaço que o operador lê no cartão.
  let(:promise_text) { 'Oi, Kennedy! Já marquei sua escova pra quinta. Qualquer coisa é só me chamar por aqui.' }
  let(:scope) do
    Ai::Manager::Scope.for_account(account, Ai::Reports::Period.from_days(30)).for_assistant(assistant)
  end

  def reply(agent: nil, flags: [], text: 'Claro, posso te ajudar com isso.', sandbox: false)
    id = ids.next
    agent ||= assistant
    create(:ai_invocation,
           account: agent.account, ai_assistant: agent, conversation_id: id,
           message_id: id, ai_response: text, auto_flags: flags, sandbox: sandbox,
           auto_flag: Ai::Invocation.primary_flag(flags), created_at: 2.days.ago)
  end

  def promises(count, agent: nil, sandbox: false)
    count.times { reply(agent: agent, flags: %w[promessa_solta], text: promise_text, sandbox: sandbox) }
  end

  describe 'o padrão que precisa virar sugestão' do
    before do
      promises(3)
      7.times { reply }
    end

    it 'aponta a promessa que o agente não tem como cumprir' do
      findings = described_class.run(scope)

      expect(findings.length).to eq(1)
      expect(findings.first[:check_key]).to eq('loose_promise')
      expect(findings.first[:evidence]['value']).to eq(30.0)
    end

    it 'propõe instrução, porque a correção é de comportamento e não de memória' do
      finding = described_class.run(scope).first

      expect(finding[:target]).to eq('prompt_version')
      expect(finding[:proposed]['instruction']).to include('AGORA')
    end

    it 'mostra a frase pela qual a resposta foi marcada, e não a resposta inteira' do
      excerpt = described_class.run(scope).first[:evidence]['excerpt']

      expect(excerpt).to include('marquei sua escova')
      expect(excerpt).not_to include('Qualquer coisa')
    end
  end

  # A coluna singular guarda só a bandeira de maior severidade. Uma resposta que
  # também inventou preço esconderia a promessa solta atrás dela.
  it 'enxerga a promessa mesmo quando outra bandeira mais grave ficou por cima' do
    3.times { reply(flags: %w[preco_inventado promessa_solta], text: promise_text) }
    7.times { reply }

    expect(described_class.run(scope).first[:check_key]).to eq('loose_promise')
  end

  describe 'o que NÃO pode virar sugestão' do
    it 'cala diante de escorregão isolado, mesmo com a taxa parecendo alta' do
      promises(2)
      3.times { reply }

      expect(described_class.run(scope)).to be_empty
    end

    it 'cala quando a ocorrência existe mas some no volume' do
      promises(3)
      60.times { reply }

      expect(described_class.run(scope)).to be_empty
    end

    it 'cala quando o agente não entregou resposta nenhuma no período' do
      expect(described_class.run(scope)).to be_empty
    end

    # A bandeira lida é uma só. Sem este caso, um `@>` trocado por um LIKE
    # solto passaria: toda resposta com qualquer bandeira viraria promessa
    # solta, e o cartão apontaria o problema errado.
    it 'não conta a resposta que levantou outra bandeira' do
      5.times { reply(flags: %w[preco_inventado], text: 'A progressiva fica R$ 189,90.') }
      5.times { reply }

      expect(described_class.run(scope)).to be_empty
    end

    # Playground fora. A resposta dada a um cliente falso não deixou ninguém
    # esperando, e contá-la mediria o quanto alguém testou o agente em vez do
    # quanto ele errou com cliente de verdade.
    it 'não audita a resposta do playground' do
      promises(5, sandbox: true)
      5.times { reply }

      expect(described_class.run(scope)).to be_empty
    end

    # A janela são 30 dias. Uma promessa de dois meses atrás já foi respondida
    # ou já não importa, e trazê-la de volta toda semana é fila que ninguém lê.
    it 'não conta a promessa que ficou fora da janela de 30 dias' do
      3.times do
        id = ids.next
        create(:ai_invocation, account: account, ai_assistant: assistant, conversation_id: id, message_id: id,
                               ai_response: promise_text, auto_flags: %w[promessa_solta],
                               auto_flag: 'promessa_solta', created_at: 45.days.ago)
      end
      7.times { reply }

      expect(described_class.run(scope)).to be_empty
    end

    # A regra mais importante desta base. O agente da outra conta pode estar
    # prometendo o que quiser: ele não é problema deste escopo.
    #
    # As dez respostas limpas do nosso agente existem para o teste não passar
    # pelo motivo errado: sem elas a verificação para no `total.zero?` e o
    # resultado seria vazio mesmo se o escopo vazasse a conta inteira.
    it 'nunca lê a resposta de um agente de outra conta' do
      10.times { reply }
      stranger = create(:ai_assistant, account: create(:account))
      promises(5, agent: stranger)

      expect(described_class.run(scope)).to be_empty
    end
  end
end

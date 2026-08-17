# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Manager::Checks::UngroundedNumber do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:ids) { (1..10_000).each }
  let(:scope) do
    Ai::Manager::Scope.for_account(account, Ai::Reports::Period.from_days(30)).for_assistant(assistant)
  end

  def reply(text:, flags: [], agent: nil)
    id = ids.next
    agent ||= assistant
    create(:ai_invocation, account: agent.account, ai_assistant: agent, conversation_id: id,
                           message_id: id, ai_response: text, auto_flags: flags,
                           auto_flag: Ai::Invocation.primary_flag(flags), created_at: 2.days.ago)
    id
  end

  def invented(text: 'A progressiva fica R$ 189,90 e você parcela em 3x.')
    reply(text: text, flags: %w[preco_inventado])
  end

  describe 'o valor que chegou ao cliente sem fonte' do
    it 'aponta uma única ocorrência, porque uma já é promessa comercial' do
      conversation = invented

      findings = described_class.run(scope)

      expect(findings.length).to eq(1)
      expect(findings.first[:severity]).to eq('critical')
      expect(findings.first[:evidence]['conversation_id']).to eq(conversation)
    end

    it 'mostra a frase com o valor e conta quantas respostas saíram assim' do
      3.times { invented }

      evidence = described_class.run(scope).first[:evidence]

      expect(evidence['excerpt']).to include('R$ 189,90')
      expect(evidence['value']).to eq(3)
    end

    it 'propõe memória, porque o que falta é o valor e não a instrução' do
      invented

      finding = described_class.run(scope).first

      expect(finding[:target]).to eq('training')
      expect(finding[:proposed]['category']).to eq('policies')
    end
  end

  describe 'o que NÃO pode virar sugestão' do
    # A guarda regenera a resposta quando pega uma invenção. Quando a
    # regeneração vem limpa, a bandeira fica mas nenhum número saiu, e cobrar
    # isso seria cobrar a guarda por ter funcionado.
    it 'cala quando a bandeira ficou mas o texto final não tem valor nenhum' do
      invented(text: 'Deixa eu confirmar esse valor com a equipe e já te retorno com o número certo.')

      expect(described_class.run(scope)).to be_empty
    end

    it 'cala quando o valor tem fonte, porque nenhuma bandeira foi levantada' do
      reply(text: 'A progressiva fica R$ 189,90, como está na nossa tabela.')

      expect(described_class.run(scope)).to be_empty
    end

    # Nem todo número é um valor. "leva 3h" e "em até 3x" são as duas frases
    # mais comuns de um salão, e uma verificação crítica que confundisse
    # qualquer dígito com preço abriria cartão sobre a duração da progressiva.
    it 'cala quando o número que sobrou no texto não é um valor' do
      invented(text: 'A progressiva leva 3h e dá pra dividir em até 3x, se preferir.')

      expect(described_class.run(scope)).to be_empty
    end

    # Isolar por conta não basta num salão com dois agentes: sem o filtro por
    # agente, o preço inventado por um vira sugestão no outro, e o operador
    # muda a memória de quem não errou.
    it 'não mistura a resposta de outro agente da mesma conta' do
      rival = create(:ai_assistant, account: account)
      reply(text: 'Fica R$ 400,00.', flags: %w[preco_inventado], agent: rival)

      expect(described_class.run(scope)).to be_empty
    end

    it 'cala quando o agente não entregou resposta nenhuma no período' do
      expect(described_class.run(scope)).to be_empty
    end

    it 'nunca lê a resposta de um agente de outra conta' do
      stranger = create(:ai_assistant, account: create(:account))
      reply(text: 'Fica R$ 400,00.', flags: %w[preco_inventado], agent: stranger)

      expect(described_class.run(scope)).to be_empty
    end
  end
end

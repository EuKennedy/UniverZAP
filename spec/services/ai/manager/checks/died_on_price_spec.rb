# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Manager::Checks::DiedOnPrice do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:ids) { (1..10_000).each }
  let(:scope) do
    Ai::Manager::Scope.for_account(account, Ai::Reports::Period.from_days(30)).for_assistant(assistant)
  end

  # Devolve os ids das conversas criadas, para que os leads apontem para
  # conversas que existem no log e a evidência tenha uma frase de verdade.
  def conversations(count, agent: nil)
    agent ||= assistant
    Array.new(count) do
      id = ids.next
      create(:ai_invocation, account: agent.account, ai_assistant: agent, conversation_id: id,
                             message_id: id, ai_response: 'Fica a partir de R$ 200.', created_at: 2.days.ago)
      id
    end
  end

  def dead_lead(conversation_id: nil, temperature: 50, reason: 'pediu_preco', status: 'open', agent: nil)
    agent ||= assistant
    create(:ai_lead_opportunity, account: agent.account, ai_assistant: agent,
                                 conversation_id: conversation_id || ids.next, block_reason: reason,
                                 status: status, temperature: temperature, last_seen_at: 2.days.ago)
  end

  describe 'a conversa que morre na pergunta de preço' do
    let(:handled) { conversations(20) }

    before do
      handled.first(3).each { |id| dead_lead(conversation_id: id) }
      dead_lead(conversation_id: handled.last, temperature: 95)
    end

    it 'aponta a proporção de conversas que pararam no valor' do
      findings = described_class.run(scope)

      expect(findings.length).to eq(1)
      expect(findings.first[:check_key]).to eq('died_on_price')
      expect(findings.first[:evidence]['value']).to eq(20.0)
    end

    it 'usa o lead mais quente como evidência, que é o que mais doeu perder' do
      evidence = described_class.run(scope).first[:evidence]

      expect(evidence['conversation_id']).to eq(handled.last)
      expect(evidence['excerpt']).to include('R$ 200')
    end

    it 'propõe memória, porque o que falta é o que responder e não como falar' do
      finding = described_class.run(scope).first

      expect(finding[:target]).to eq('training')
      expect(finding[:proposed]['category']).to eq('sales')
      expect(finding[:proposed]['content']).to be_present
    end

    # O cruzamento com Ai::Reports::CommercialMetrics: o agendamento feito pelo
    # belezaki não tem linha na nossa agenda, só no ledger de receita, e é o
    # painel comercial que sabe contá-lo como agendamento.
    it 'conta contra o que o mesmo agente fechou no período' do
      create(:ai_revenue_event, account: account, ai_assistant: assistant, occurred_at: 2.days.ago,
                                recorded_by: Ai::Belezaki::BookingRecorder::RECORDER,
                                external_ref: "#{Ai::Belezaki::BookingRecorder::REF_PREFIX}901")

      expect(described_class.run(scope).first[:rationale]).to include('fechou 1 agendamento')
    end
  end

  describe 'o que NÃO pode virar sugestão' do
    it 'cala quando a proporção é pequena, mesmo com casos suficientes' do
      conversations(40)
      3.times { dead_lead }

      expect(described_class.run(scope)).to be_empty
    end

    it 'cala quando são poucos casos, mesmo com a proporção alta' do
      conversations(20)
      2.times { dead_lead }

      expect(described_class.run(scope)).to be_empty
    end

    it 'não conta lead que parou por outro motivo' do
      conversations(20)
      4.times { dead_lead(reason: 'sem_vaga') }

      expect(described_class.run(scope)).to be_empty
    end

    # Ganho não morreu, e o que um humano já está perseguindo não precisa de
    # cartão novo toda semana.
    it 'não conta lead ganho nem lead que alguém já está seguindo' do
      conversations(20)
      2.times { dead_lead(status: 'won') }
      2.times { dead_lead(status: 'followed') }

      expect(described_class.run(scope)).to be_empty
    end

    it 'cala quando o agente não teve conversa nenhuma no período' do
      4.times { dead_lead }

      expect(described_class.run(scope)).to be_empty
    end

    # `last_seen_at` e não `created_at`: um lead esquenta e esfria, e a pergunta
    # da rodada é quais se mexeram na janela. Um lead parado há dois meses não
    # descreve a operação desta semana.
    it 'não conta o lead que não se mexeu dentro da janela' do
      conversations(20)
      4.times do
        id = ids.next
        create(:ai_lead_opportunity, account: account, ai_assistant: assistant, conversation_id: id,
                                     block_reason: 'pediu_preco', status: 'open', last_seen_at: 45.days.ago)
      end

      expect(described_class.run(scope)).to be_empty
    end

    # Dois agentes no mesmo salão têm filas separadas. O filtro por conta não
    # ajuda aqui: é o filtro por agente que impede a sugestão de chegar para
    # quem não perdeu conversa nenhuma.
    it 'não conta o lead de outro agente da mesma conta' do
      conversations(20)
      rival = create(:ai_assistant, account: account)
      4.times { dead_lead(agent: rival) }

      expect(described_class.run(scope)).to be_empty
    end

    it 'nunca lê o lead de um agente de outra conta' do
      conversations(20)
      stranger = create(:ai_assistant, account: create(:account))
      4.times { dead_lead(agent: stranger) }

      expect(described_class.run(scope)).to be_empty
    end
  end
end

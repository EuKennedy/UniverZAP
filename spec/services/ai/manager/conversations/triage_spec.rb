# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Manager::Conversations::Triage do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:now) { Time.zone.parse('2026-08-31 18:00:00') }

  # Uma conversa com fala do cliente e, opcionalmente, resposta depois.
  # `outgoing_ago: nil` é o caso mais grave: ninguém respondeu nunca.
  def talk(incoming_ago:, outgoing_ago: nil, status: 'open', name: 'Fernanda', **extra)
    target = extra[:on] || account
    sandbox = extra[:sandbox]
    contact = create(:contact, account: target, name: name)
    conversation = create(:conversation, account: target, inbox: inbox_for(target), contact: contact,
                                         additional_attributes: sandbox ? { 'athenas_sandbox' => true } : {})
    say(conversation, :incoming, 'Oi, quanto fica a mechinha?', now - incoming_ago)
    say(conversation, :outgoing, 'Já te respondo!', now - outgoing_ago) if outgoing_ago
    # O estado vai DEPOIS das mensagens: Message#reopen_conversation reabre a
    # conversa resolvida ou adiada quando chega mensagem nova, então criá-la já
    # resolvida e escrever em seguida devolvia uma conversa aberta. Era o teste
    # montado errado, não o filtro de estado.
    conversation.update!(status: status) unless status == 'open'
    conversation
  end

  def inbox_for(target)
    target == account ? inbox : create(:inbox, account: target)
  end

  def say(conversation, type, content, at)
    create(:message, account: conversation.account, inbox: conversation.inbox, conversation: conversation,
                     message_type: type, content: content, created_at: at)
  end

  def findings_for(key)
    described_class.new(account: account, since: now - 30.days, now: now).findings
                   .select { |finding| finding[:case_key] == key }
  end

  describe 'cliente esperando' do
    it 'aponta quem escreveu e nunca foi respondido' do
      talk(incoming_ago: 30.hours)

      finding = findings_for('cliente_esperando').first

      expect(finding[:severity]).to eq('critical')
      expect(finding[:detail]).to include('Fernanda', '30 horas')
    end

    it 'sobe a gravidade com o relógio, porque o mesmo silêncio não vale o mesmo às 7h e às 30h' do
      talk(incoming_ago: 7.hours, name: 'Ana')

      expect(findings_for('cliente_esperando').first[:severity]).to eq('medium')
    end

    it 'marca como sem resposta nenhuma quando ninguém falou do nosso lado' do
      talk(incoming_ago: 30.hours)

      expect(findings_for('cliente_esperando').first[:author]).to eq('none')
    end

    it 'leva junto o trecho do que a cliente escreveu, que é o que faz o cartão ser lido' do
      talk(incoming_ago: 30.hours)

      expect(findings_for('cliente_esperando').first[:excerpt]).to eq('Oi, quanto fica a mechinha?')
    end
  end

  describe 'o que NÃO pode virar cartão' do
    it 'cala quando alguém respondeu depois da última fala do cliente' do
      talk(incoming_ago: 30.hours, outgoing_ago: 20.hours)

      expect(findings_for('cliente_esperando')).to be_empty
    end

    # Abaixo do piso o silêncio ainda é atendimento normal. Um painel que acusa
    # a conversa de vinte minutos atrás é um painel que ninguém consegue usar.
    it 'cala abaixo do piso de seis horas' do
      talk(incoming_ago: 2.hours)

      expect(findings_for('cliente_esperando')).to be_empty
    end

    # Resolvida é decisão de alguém. Acusar o silêncio de uma conversa encerrada
    # transforma o painel numa lista do que o operador já resolveu.
    it 'cala quando a conversa foi resolvida' do
      talk(incoming_ago: 30.hours, status: 'resolved')

      expect(findings_for('cliente_esperando')).to be_empty
    end

    it 'cala quando a conversa foi adiada' do
      talk(incoming_ago: 30.hours, status: 'snoozed')

      expect(findings_for('cliente_esperando')).to be_empty
    end

    # Conversa de playground é conversa de verdade no banco. Um cartão dizendo
    # "cliente esperando há 30h" sobre um teste que o próprio operador abandonou
    # é o falso positivo que faz a aba perder credibilidade na primeira semana.
    it 'nunca olha conversa do playground' do
      talk(incoming_ago: 30.hours, sandbox: true)

      expect(findings_for('cliente_esperando')).to be_empty
    end

    # A regra mais importante desta base.
    it 'nunca olha conversa de outra conta' do
      talk(incoming_ago: 30.hours, on: create(:account))

      expect(described_class.new(account: account, since: now - 30.days, now: now).findings).to be_empty
    end
  end

  describe 'quem falou por último' do
    it 'diz equipe quando a última resposta não saiu do agente' do
      talk(incoming_ago: 30.hours, outgoing_ago: 40.hours)

      expect(findings_for('cliente_esperando').first[:author]).to eq('human')
    end

    # A prova de que a mensagem saiu do agente é a linha em ai_invocations que
    # aponta para ela, e não o `sender_type`: a convenção de remetente muda com
    # o canal, a linha do log não muda nunca.
    it 'diz agente quando a última resposta tem invocação apontando para ela' do
      conversation = talk(incoming_ago: 30.hours, outgoing_ago: 40.hours)
      reply = conversation.messages.where(message_type: :outgoing).last
      create(:ai_invocation, account: account, ai_assistant: assistant,
                             conversation_id: conversation.id, message_id: reply.id, created_at: now - 40.hours)

      expect(findings_for('cliente_esperando').first[:author]).to eq('agent')
    end
  end

  describe 'sinais do log do agente' do
    def reply_twice(conversation, text, flags: [])
      2.times do |index|
        create(:ai_invocation, account: account, ai_assistant: assistant,
                               conversation_id: conversation.id, message_id: (conversation.id * 100) + index,
                               ai_response: text, auto_flags: flags,
                               auto_flag: Ai::Invocation.primary_flag(flags), created_at: now - 3.hours)
      end
    end

    it 'aponta o agente que ficou repetindo a mesma resposta' do
      conversation = talk(incoming_ago: 3.hours)
      reply_twice(conversation, 'Me confirma seu telefone, por favor.')

      finding = findings_for('agente_repetiu').first

      expect(finding[:metadata]['repeats']).to eq(2)
      expect(finding[:excerpt]).to include('Me confirma seu telefone')
    end

    it 'traduz a bandeira do guardrail em português no lugar de mostrar o nome da coluna' do
      conversation = talk(incoming_ago: 3.hours)
      reply_twice(conversation, 'A progressiva fica R$ 189,90.', flags: %w[preco_inventado])

      expect(findings_for('resposta_marcada').first[:detail]).to include('não saiu da base de conhecimento')
    end

    # `cliente_insatisfeito` fala do CLIENTE e as outras bandeiras falam do que
    # o agente disse. No mesmo caso, o cartão anunciaria "o agente disse algo
    # marcado" sobre uma cliente que estava reclamando: culpado errado no único
    # lugar onde o operador confia no rótulo.
    it 'separa a insatisfação do cliente das bandeiras sobre a fala do agente' do
      conversation = talk(incoming_ago: 3.hours, name: 'Marta')
      reply_twice(conversation, 'Sinto muito pelo ocorrido.', flags: %w[cliente_insatisfeito])

      expect(findings_for('resposta_marcada')).to be_empty
      expect(findings_for('cliente_insatisfeito').first[:detail]).to include('Marta')
    end
  end

  describe 'quem vai para a leitura por modelo' do
    # O piso para MANDAR LER é mais baixo que o piso para ACUSAR: a conversa
    # parada há duas horas ainda não é um cartão, mas já pode ser uma compra
    # travada, e é esse caso que ainda dá para salvar.
    it 'inclui a conversa parada há duas horas, que ainda não vira cartão sozinha' do
      conversation = talk(incoming_ago: 3.hours)

      triage = described_class.new(account: account, since: now - 30.days, now: now)

      expect(triage.candidates).to include(conversation.id)
      expect(triage.findings).to be_empty
    end

    it 'não manda ler conversa recém-respondida e curta, que não tem o que interpretar' do
      talk(incoming_ago: 30.minutes, outgoing_ago: 10.minutes)

      expect(described_class.new(account: account, since: now - 30.days, now: now).candidates).to be_empty
    end

    it 'coloca quem espera há mais tempo na frente, porque é quem some primeiro' do
      recente = talk(incoming_ago: 4.hours, name: 'Bia')
      antiga = talk(incoming_ago: 40.hours, name: 'Carla')

      expect(described_class.new(account: account, since: now - 30.days, now: now).candidates)
        .to eq([antiga.id, recente.id])
    end
  end
end

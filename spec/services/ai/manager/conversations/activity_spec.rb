# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Manager::Conversations::Activity do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:now) { Time.zone.parse('2026-09-01 18:00:00') }

  def talk(incoming_ago:, outgoing_ago: nil)
    conversation = create(:conversation, account: account, inbox: inbox)
    say(conversation, :incoming, now - incoming_ago)
    say(conversation, :outgoing, now - outgoing_ago) if outgoing_ago
    conversation
  end

  def say(conversation, type, at)
    create(:message, account: account, inbox: inbox, conversation: conversation,
                     message_type: type, content: 'oi', created_at: at)
  end

  def activity
    described_class.new(account: account, since: now - 30.days)
  end

  describe 'o retrato da janela' do
    it 'separa a última fala do cliente da última resposta' do
      talk(incoming_ago: 30.hours, outgoing_ago: 40.hours)

      row = activity.rows.values.first

      expect(row.last_in).to be_within(1.minute).of(now - 30.hours)
      expect(row.last_out).to be_within(1.minute).of(now - 40.hours)
    end

    # A consulta agrega com apelido e é lida como atributo. Sem este teste, um
    # dia em que os valores voltassem como String passaria despercebido até
    # alguém comparar data com texto em produção.
    it 'devolve hora como hora e contagem como número, e não como texto' do
      talk(incoming_ago: 3.hours, outgoing_ago: 2.hours)

      row = activity.rows.values.first

      expect(row.last_in).to be_a(ActiveSupport::TimeWithZone).or be_a(Time)
      expect(row.incoming).to be_a(Integer)
      expect(row.outgoing).to eq(1)
    end

    it 'sabe quem está esperando e por quantas horas' do
      talk(incoming_ago: 30.hours)

      row = activity.rows.values.first

      expect(row).to be_waiting
      expect(row.waited_hours(now)).to eq(30.0)
    end

    it 'não chama de esperando quem já foi respondido' do
      talk(incoming_ago: 30.hours, outgoing_ago: 20.hours)

      expect(activity.rows.values.first).not_to be_waiting
    end
  end

  describe 'a ordem, que decide quem sobrevive ao teto' do
    # A regressão que este teste tranca: ordenar só por atividade recente
    # descartava primeiro quem está esperando há mais tempo, porque uma conversa
    # sem resposta há cinco dias tem, por definição, atividade ANTIGA. O teto
    # jogava fora exatamente as pessoas que a tela existe para encontrar.
    it 'põe quem espera na frente de quem acabou de ser respondido' do
      esperando = talk(incoming_ago: 40.hours)
      talk(incoming_ago: 2.hours, outgoing_ago: 1.hour)

      expect(activity.rows.keys.first).to eq(esperando.id)
    end

    it 'entre duas que esperam, a mais recente vem primeiro' do
      antiga = talk(incoming_ago: 40.hours)
      recente = talk(incoming_ago: 8.hours)

      expect(activity.rows.keys).to eq([recente.id, antiga.id])
    end

    it 'trata quem nunca foi respondido como quem espera' do
      nunca = talk(incoming_ago: 20.hours)
      talk(incoming_ago: 1.hour, outgoing_ago: 30.minutes)

      expect(activity.rows.keys.first).to eq(nunca.id)
    end
  end

  describe 'o teto' do
    it 'não se diz cortado quando coube tudo' do
      talk(incoming_ago: 3.hours)

      expect(activity).not_to be_capped
    end

    # Uma varredura que corta em silêncio se apresenta como completa, e é assim
    # que alguém conclui que está tudo bem quando não está.
    it 'se diz cortado quando bateu no limite' do
      stub_const("#{described_class}::MAX_CONVERSATIONS", 1)
      talk(incoming_ago: 3.hours)
      talk(incoming_ago: 4.hours)

      expect(activity).to be_capped
    end
  end

  it 'nunca enxerga mensagem de outra conta' do
    outra = create(:account)
    conversation = create(:conversation, account: outra, inbox: create(:inbox, account: outra))
    create(:message, account: outra, inbox: conversation.inbox, conversation: conversation,
                     message_type: :incoming, content: 'oi', created_at: now - 3.hours)

    expect(activity.rows).to be_empty
  end
end

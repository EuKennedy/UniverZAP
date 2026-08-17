# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Manager::Scorecard do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:ids) { (1..10_000).each }
  let(:scope) do
    Ai::Manager::Scope.for_account(account, Ai::Reports::Period.from_days(30)).for_assistant(assistant)
  end
  let(:scores) { described_class.new(scope: scope).perform }

  # Um turno como ele existe em produção: várias chamadas com o MESMO
  # message_id, e o texto final gravado só na última. A janela é escolhida com
  # `travel_to` em vez de um parâmetro de data, para a lista de argumentos não
  # virar um formulário.
  def turn(conversation_id:, rows: 1, flags: [], text: 'Tudo certo por aqui!', cost: 0.0)
    message_id = ids.next
    rows.times do |index|
      last = index == rows - 1
      create(:ai_invocation,
             account: account, ai_assistant: assistant, conversation_id: conversation_id,
             message_id: message_id, ai_response: last ? text : nil,
             auto_flags: last ? flags : [], auto_flag: last ? Ai::Invocation.primary_flag(flags) : nil,
             cost_brl: cost)
    end
  end

  def sale(conversation_id)
    create(:ai_revenue_event, account: account, ai_assistant: assistant,
                              conversation_id: conversation_id, occurred_at: Time.current)
  end

  # Montado à mão como o resto dos specs de agenda desta base: a linha depende
  # de uma conexão e de um profissional, e não existe factory para nenhum dos dois.
  #
  # A conversa tem que ser real. `ai_calendar_appointments.conversation_id` tem
  # chave estrangeira para `conversations`, e um id inventado aqui não vira uma
  # asserção vermelha: vira um INSERT recusado que derruba o exemplo inteiro.
  def booking(conversation_id)
    connection = Ai::Calendar::Connection.create!(
      ai_assistant: assistant, account: account, google_email: 'salao@gmail.com', encrypted_refresh_token: 'rt'
    )
    professional = connection.professionals.create!(
      ai_assistant_id: assistant.id, account_id: account.id, name: 'Ana', calendar_id: 'primary'
    )
    Ai::Calendar::Appointment.create!(
      ai_calendar_professional_id: professional.id, ai_assistant_id: assistant.id, account_id: account.id,
      contact_id: create(:contact, account: account).id, conversation_id: conversation_id,
      google_event_id: "evt-#{conversation_id}", starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour,
      status: 'booked'
    )
  end

  describe 'as três notas' do
    before do
      turn(conversation_id: 1, cost: 0.5)
      turn(conversation_id: 2, cost: 0.5)
      sale(1)
    end

    it 'devolve as três separadas, cada uma na sua unidade' do
      expect(scores.keys).to eq(%i[reliability conversion cost])
      expect(scores[:reliability][:value]).to eq(100.0)
      expect(scores[:conversion][:value]).to eq(50.0)
      expect(scores[:cost][:value]).to eq(50.0)
    end

    it 'nunca colapsa as três num número só' do
      expect(scores).not_to have_key(:score)
      expect(scores.values.map { |note| note.keys }.uniq).to eq([%i[value previous change]])
    end
  end

  describe 'confiabilidade' do
    # O falso positivo que derrubaria a nota de todo agente que usa a agenda:
    # só a última chamada do turno recebe o texto, e cobrar linha a linha
    # marcaria como falha exatamente os turnos que funcionaram.
    it 'não pune o turno de várias chamadas em que só a última tem texto' do
      turn(conversation_id: 1, rows: 4)

      expect(scores[:reliability][:value]).to eq(100.0)
    end

    it 'cai quando uma bandeira automática ficou na resposta' do
      turn(conversation_id: 1)
      turn(conversation_id: 2, flags: %w[preco_inventado])

      expect(scores[:reliability][:value]).to eq(50.0)
    end

    it 'conta como falha o turno que terminou sem texto nenhum' do
      turn(conversation_id: 1)
      turn(conversation_id: 2, text: nil)

      expect(scores[:reliability][:value]).to eq(50.0)
    end
  end

  describe 'conversão' do
    # Somar as duas pontas produziria conversão acima de 100% sem que nada de
    # anormal tivesse acontecido.
    it 'conta uma vez a conversa que agendou e vendeu' do
      converted = create(:conversation, account: account)
      other = create(:conversation, account: account)
      turn(conversation_id: converted.id)
      turn(conversation_id: other.id)
      sale(converted.id)
      booking(converted.id)

      expect(scores[:conversion][:value]).to eq(50.0)
    end
  end

  # Zero lê como um agente que fracassou. A verdade é que ninguém falou com ele,
  # e a tela precisa poder dizer isso.
  describe 'a nota vazia' do
    it 'devolve nulo, e não zero, quando não há base para calcular' do
      expect(scores[:reliability][:value]).to be_nil
      expect(scores[:conversion][:value]).to be_nil
      expect(scores[:cost][:value]).to be_nil
    end

    it 'não inventa variação quando o período anterior também está vazio' do
      turn(conversation_id: 1)

      expect(scores[:reliability][:change]).to be_nil
    end
  end

  describe 'a comparação com o período anterior' do
    before do
      turn(conversation_id: 1)
      turn(conversation_id: 2)
      sale(1)
      travel_to(40.days.ago) do
        4.times { |n| turn(conversation_id: 100 + n) }
        sale(100)
      end
    end

    it 'lê a régua na história do próprio agente, e não no irmão do lado' do
      expect(scores[:conversion][:previous]).to eq(25.0)
      expect(scores[:conversion][:value]).to eq(50.0)
      expect(scores[:conversion][:change]).to eq(100.0)
    end
  end
end

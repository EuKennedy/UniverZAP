# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Manager::Checks::PromisedTimeMismatch do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:zone) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:connection) do
    Ai::Calendar::Connection.create!(
      ai_assistant: assistant, account: account, google_email: 'salao@gmail.com', encrypted_refresh_token: 'rt'
    )
  end
  # Existir já define o fuso do negócio para o relógio da conta, que é o fuso em
  # que o horário agendado tem que ser lido.
  let(:professional) do
    connection.professionals.create!(
      ai_assistant_id: assistant.id, account_id: account.id,
      name: 'Ana', calendar_id: 'primary', timezone: 'America/Sao_Paulo'
    )
  end
  # Conversas de verdade, e não um número escolhido a dedo:
  # `ai_calendar_appointments.conversation_id` tem chave estrangeira para
  # `conversations`, então um id inventado estoura o INSERT e leva o arquivo
  # inteiro junto antes de a primeira asserção rodar.
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:other_conversation) { create(:conversation, account: account) }
  let(:booked_at) { 2.days.ago }
  let(:ids) { (1..10_000).each }
  let(:scope) do
    Ai::Manager::Scope.for_account(account, Ai::Reports::Period.from_days(30)).for_assistant(assistant)
  end

  before { professional }

  def book(hour, minute = 0, status: 'booked', created_at: nil)
    starts_at = zone.local(2026, 9, 3, hour, minute)
    at = created_at || booked_at
    Ai::Calendar::Appointment.create!(
      ai_calendar_professional_id: professional.id, ai_assistant_id: assistant.id,
      account_id: account.id, contact_id: contact.id, conversation_id: conversation.id,
      google_event_id: "evt-#{SecureRandom.hex(4)}", starts_at: starts_at, ends_at: starts_at + 1.hour,
      status: status, created_at: at, updated_at: at
    )
  end

  def confirm(text, appointment, after: 1.minute, conversation_id: nil)
    create(:ai_invocation, account: account, ai_assistant: assistant,
                           conversation_id: conversation_id || appointment.conversation_id,
                           message_id: ids.next, ai_response: text,
                           created_at: appointment.created_at + after)
  end

  # A agenda de um segundo agente do mesmo salão. Montada à mão porque não
  # existe factory para conexão nem para profissional nesta base.
  def rival_agenda(rival)
    Ai::Calendar::Connection.create!(
      ai_assistant: rival, account: account, google_email: 'outra@gmail.com', encrypted_refresh_token: 'rt'
    ).professionals.create!(
      ai_assistant_id: rival.id, account_id: account.id,
      name: 'Bia', calendar_id: 'bia', timezone: 'America/Sao_Paulo'
    )
  end

  # A falha real do log: a ferramenta recebeu 13:00, devolveu inicio=13:00, e a
  # mensagem que o cliente recebeu falava em 14h.
  describe 'a divergência que existiu de verdade' do
    before { confirm('Prontinho, Kennedy! Agendei sua escova pra quinta às 14h.', book(13)) }

    it 'aponta a confirmação com o horário que a agenda nunca teve' do
      findings = described_class.run(scope)

      expect(findings.length).to eq(1)
      expect(findings.first[:evidence]['conversation_id']).to eq(conversation.id)
      expect(findings.first[:evidence]['value']).to eq(1)
    end

    it 'trata como crítica e propõe mexer na instrução, não na memória' do
      finding = described_class.run(scope).first

      expect(finding[:severity]).to eq('critical')
      expect(finding[:target]).to eq('prompt_version')
      expect(finding[:proposed]['instruction']).to be_present
    end

    it 'mostra a frase onde o horário errado está, e não a resposta inteira' do
      expect(described_class.run(scope).first[:evidence]['excerpt']).to include('14h')
    end
  end

  # O minuto só é comparado quando ele foi dito. Sem este par, a metade do
  # `matches?` que confere minuto ficaria sem prova nenhuma: apagar a comparação
  # de minuto passaria calado, e "às 14h15" para uma cadeira reservada às 14h30
  # é o cliente chegando quinze minutos antes de a anterior terminar.
  describe 'o minuto dito' do
    it 'acusa quando o minuto não é o que ficou na agenda' do
      confirm('Fechado, te espero às 14h15.', book(14, 30))

      expect(described_class.run(scope).first[:evidence]['excerpt']).to include('14h15')
    end

    it 'fica calado quando o minuto é exatamente o da agenda' do
      confirm('Fechado, te espero às 14h30.', book(14, 30))

      expect(described_class.run(scope)).to be_empty
    end
  end

  # Falso positivo é o que faz o operador parar de ler a fila, então cada uma
  # destas vale tanto quanto a de cima.
  describe 'o que NÃO pode virar sugestão' do
    it 'fica calado quando a confirmação repete o horário certo' do
      confirm('Prontinho! Agendei sua escova pra quinta às 13h.', book(13))

      expect(described_class.run(scope)).to be_empty
    end

    it 'fica calado quando a resposta cita vários horários e um deles é o agendado' do
      confirm('Tinha 11h e 13h livres, deixei marcado às 13h pra você.', book(13))

      expect(described_class.run(scope)).to be_empty
    end

    it 'fica calado quando a confirmação não fala horário nenhum' do
      confirm('Prontinho, tá tudo certo! Qualquer coisa me chama por aqui.', book(13))

      expect(described_class.run(scope)).to be_empty
    end

    # "às 2h da tarde" é 14:00 em português, e recusar isso encheria a fila de
    # divergência que não existe.
    it 'entende a hora falada em formato de doze horas' do
      confirm('Fechado! Te espero às 2h da tarde.', book(14))

      expect(described_class.run(scope)).to be_empty
    end

    it 'ignora a hora sem minuto quando o agendamento cai na mesma hora' do
      confirm('Marquei às 13h pra você.', book(13, 30))

      expect(described_class.run(scope)).to be_empty
    end

    # "leva 3h" e "às 3h" são a mesma coisa para uma regex. Confundir a duração
    # do serviço com o horário prometido seria o falso positivo mais caro que
    # esta verificação conseguiria produzir, porque ela é crítica.
    it 'não confunde duração de serviço com horário prometido' do
      confirm('Prontinho! A progressiva leva 3h, então reserve a tarde.', book(13))

      expect(described_class.run(scope)).to be_empty
    end

    it 'não compara com uma resposta de outra conversa' do
      confirm('Agendei pra você às 14h.', book(13), conversation_id: other_conversation.id)

      expect(described_class.run(scope)).to be_empty
    end

    # Passou da janela, a resposta é sobre outra coisa, e comparar seria inventar.
    it 'não compara com uma resposta muito posterior ao agendamento' do
      confirm('Aliás, o salão abre às 14h no sábado.', book(13), after: 45.minutes)

      expect(described_class.run(scope)).to be_empty
    end

    # A confirmação vem DEPOIS que a linha entrou na agenda. Uma resposta
    # anterior está falando de um horário que ainda não tinha sido escrito, e
    # cobrar divergência dela seria cobrar o agente por ter perguntado.
    it 'não compara com uma resposta anterior ao agendamento' do
      confirm('Consigo te encaixar às 14h?', book(13), after: -5.minutes)

      expect(described_class.run(scope)).to be_empty
    end

    # Um agendamento cancelado não tem ninguém chegando na hora errada. Sem
    # este caso, tirar o `.booked` da consulta passaria despercebido e a fila
    # encheria de divergência sobre horário que não existe mais.
    it 'não compara com um agendamento que foi cancelado' do
      confirm('Agendei pra você às 14h.', book(13, status: 'cancelled'))

      expect(described_class.run(scope)).to be_empty
    end

    # A janela da auditoria são 30 dias. Um agendamento de dois meses atrás já
    # aconteceu, e reabrir a discussão sobre ele toda semana é o que faz o
    # operador parar de abrir a fila.
    it 'não olha o agendamento que ficou fora da janela' do
      confirm('Agendei pra você às 14h.', book(13, created_at: 45.days.ago))

      expect(described_class.run(scope)).to be_empty
    end

    # O filtro por conta já é provado nas outras verificações; o que este caso
    # prova é o filtro por AGENTE, que é o único que separa dois agentes do
    # mesmo salão. Sem ele a sugestão chega para quem não errou nada.
    it 'não olha o agendamento de outro agente da mesma conta' do
      rival = create(:ai_assistant, account: account)
      bia = rival_agenda(rival)
      starts_at = zone.local(2026, 9, 3, 13, 0)
      Ai::Calendar::Appointment.create!(
        ai_calendar_professional_id: bia.id, ai_assistant_id: rival.id, account_id: account.id,
        contact_id: contact.id, conversation_id: conversation.id, google_event_id: 'evt-bia',
        starts_at: starts_at, ends_at: starts_at + 1.hour, status: 'booked',
        created_at: booked_at, updated_at: booked_at
      )
      create(:ai_invocation, account: account, ai_assistant: rival, conversation_id: conversation.id,
                             message_id: ids.next, ai_response: 'Agendei pra você às 14h.',
                             created_at: booked_at + 1.minute)

      expect(described_class.run(scope)).to be_empty
    end

    it 'fica calado quando não houve agendamento nenhum no período' do
      expect(described_class.run(scope)).to be_empty
    end
  end
end

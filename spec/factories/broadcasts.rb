# frozen_string_literal: true

FactoryBot.define do
  factory :broadcast do
    account
    sequence(:name) { |n| "Disparo #{n}" }
    # Sem inbox por padrao: `mode_matches_inbox` so julga o par quando alguem o
    # define, entao o factory base vale para qualquer modo. Os testes que
    # exercitam o envio passam inbox e mode juntos.
    mode { 'waha' }
    message { { 'text' => 'Oi' } }
    audience { {} }
    throttle { {} }
  end

  factory :broadcast_recipient do
    broadcast
    contact
    status { :pending }
  end
end

FactoryBot.define do
  factory :scheduled_message do
    conversation
    content { 'Oi {primeiro_nome}, tudo bem?' }
    send_at { 1.hour.from_now }
  end

  factory :message_sequence do
    account
    name { 'Lembrete e pós' }
    steps { [{ 'offset_minutes' => -1440, 'text' => 'Lembrete: amanhã é sua {servico}!' }] }
  end
end

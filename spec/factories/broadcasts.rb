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

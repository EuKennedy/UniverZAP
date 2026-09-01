FactoryBot.define do
  factory :ai_manager_conversation_finding, class: 'Ai::Manager::ConversationFinding' do
    account
    conversation_id { 1 }
    conversation_display_id { 1 }
    case_key { 'cliente_esperando' }
    severity { 'high' }
    title { 'Cliente esperando resposta' }
    detail { 'Fernanda escreveu há 30 horas e ninguém respondeu depois disso.' }
    excerpt { 'Consigo horário sábado?' }
    author { 'none' }
    source { 'triage' }
    value_cents_brl { 0 }
    occurred_at { 30.hours.ago }
    last_seen_at { Time.current }
    metadata { {} }
  end
end

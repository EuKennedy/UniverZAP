FactoryBot.define do
  factory :ai_revenue_event, class: 'Ai::RevenueEvent' do
    account { ai_assistant.account }
    ai_assistant
    source { 'recuperado' }
    amount_brl { 250.0 }
    occurred_at { Time.current }
    recorded_by { 'operator' }
  end
end

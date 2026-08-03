FactoryBot.define do
  factory :ai_lead_opportunity, class: 'Ai::LeadOpportunity' do
    account { ai_assistant.account }
    ai_assistant
    contact { association :contact, account: ai_assistant.account }
    temperature { 50 }
    status { 'open' }
    last_seen_at { Time.current }
  end
end

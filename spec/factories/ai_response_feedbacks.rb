FactoryBot.define do
  factory :ai_response_feedback, class: 'Ai::ResponseFeedback' do
    account { ai_assistant.account }
    ai_assistant
    ai_invocation { association :ai_invocation, account: ai_assistant.account, ai_assistant: ai_assistant }
    reviewer { association :user, account: ai_assistant.account, role: :administrator }
    rating { 'up' }
  end
end

FactoryBot.define do
  factory :ai_prompt_version, class: 'Ai::PromptVersion' do
    account { ai_assistant.account }
    ai_assistant
    sequence(:version) { |n| "v#{n}" }
    status { 'draft' }
    system_prompt { 'Você é um atendente.' }
  end
end

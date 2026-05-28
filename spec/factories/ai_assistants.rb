FactoryBot.define do
  factory :ai_assistant, class: 'Ai::Assistant' do
    account
    sequence(:name) { |n| "Athenas #{n}" }
    role { 'Atendente' }
    tone { 'friendly' }
    provider { 'anthropic' }
    model { 'claude-sonnet-4-5' }
    system_prompt { 'You are a helpful assistant.' }
    temperature { 0.3 }
    max_tokens { 1024 }
    active { true }
    autopilot_enabled { false }
  end
end

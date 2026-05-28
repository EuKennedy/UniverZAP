FactoryBot.define do
  factory :ai_invocation, class: 'Ai::Invocation' do
    account
    ai_assistant
    phase { 'main' }
    status { 'success' }
    model { 'claude-sonnet-4-5' }
    input_tokens { 1_000 }
    output_tokens { 500 }
    cost_usd { 0.012 }
    duration_ms { 350 }
  end
end

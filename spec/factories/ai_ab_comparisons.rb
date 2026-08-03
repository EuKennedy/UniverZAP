FactoryBot.define do
  factory :ai_ab_comparison, class: 'Ai::AbComparison' do
    account { ai_assistant.account }
    ai_assistant
    ai_prompt_version { association :ai_prompt_version, ai_assistant: ai_assistant }
    ai_invocation { association :ai_invocation, account: ai_assistant.account, ai_assistant: ai_assistant }
    response_b { 'resposta candidata' }
    telemetry_b { { 'cost_brl' => 0.01, 'latency_ms' => 900 } }
  end
end

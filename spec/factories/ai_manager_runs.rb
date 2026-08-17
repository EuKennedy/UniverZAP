FactoryBot.define do
  factory :ai_manager_run, class: 'Ai::Manager::Run' do
    account
    status { 'done' }
    triggered_by { 'schedule' }
    started_at { Time.current }
    finished_at { Time.current }
    period_start { 30.days.ago }
    period_end { Time.current }
    conversations_analysed { 40 }
    cost_cents_brl { 0 }
    summary { { 'insufficient_data' => false, 'analysed' => 40, 'suggestions_created' => 0 } }
  end
end

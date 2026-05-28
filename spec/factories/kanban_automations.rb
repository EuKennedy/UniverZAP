# frozen_string_literal: true

FactoryBot.define do
  factory :kanban_automation do
    account
    funnel { association :funnel, account: account }
    sequence(:name) { |n| "Automation #{n}" }
    event_name { 'task_created' }
    conditions { {} }
    actions { [{ 'type' => 'set_priority', 'params' => { 'priority' => 'high' } }] }
    active { true }
  end
end

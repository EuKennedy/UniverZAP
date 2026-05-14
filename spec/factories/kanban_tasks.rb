# frozen_string_literal: true

FactoryBot.define do
  factory :kanban_task do
    account
    funnel { association :funnel, account: account }
    funnel_stage { association :funnel_stage, funnel: funnel }
    sequence(:title) { |n| "Task #{n}" }
    priority { :none }
  end
end

# frozen_string_literal: true

FactoryBot.define do
  factory :task do
    account
    created_by_user { association :user, account: account }
    sequence(:title) { |n| "Task #{n}" }
    description { {} }
    status { :open }
    urgency { :none }
    notify_assignees { true }
  end
end

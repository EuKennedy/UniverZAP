# frozen_string_literal: true

FactoryBot.define do
  factory :task_activity do
    task
    user { association :user, account: task.account }
    action { 'created' }
    payload { {} }
  end
end

# frozen_string_literal: true

FactoryBot.define do
  factory :task_assignee do
    task
    user { association :user, account: task.account }
  end
end

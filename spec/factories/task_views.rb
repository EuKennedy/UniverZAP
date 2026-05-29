# frozen_string_literal: true

FactoryBot.define do
  factory :task_view do
    account
    user { association :user, account: account }
    sequence(:name) { |n| "View #{n}" }
    filters { { scope: 'mine', urgency: 'high' } }
    position { 0 }
    is_default { false }
  end
end

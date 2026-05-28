# frozen_string_literal: true

FactoryBot.define do
  factory :kanban_webhook_subscription do
    account
    sequence(:name) { |n| "Webhook #{n}" }
    url { 'https://example.com/hook' }
    events { [] }
    secret { SecureRandom.hex(32) }
    active { true }
  end
end

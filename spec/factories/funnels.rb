# frozen_string_literal: true

FactoryBot.define do
  factory :funnel do
    account
    sequence(:name) { |n| "Funnel #{n}" }
    description { 'Sample funnel' }
  end
end

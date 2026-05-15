# frozen_string_literal: true

FactoryBot.define do
  factory :funnel_stage do
    funnel
    sequence(:name) { |n| "Stage #{n}" }
    color { '#3B82F6' }
  end
end

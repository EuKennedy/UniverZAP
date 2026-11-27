# frozen_string_literal: true

FactoryBot.define do
  factory :account do
    sequence(:name) { |n| "Account #{n}" }
    status { 'active' }
    domain { 'test.com' }
    support_email { 'support@test.com' }
    # New accounts start with no AI credit; test accounts get some so AI flows can run.
    token_credit_balance_cents_brl { 2_500 }
  end
end

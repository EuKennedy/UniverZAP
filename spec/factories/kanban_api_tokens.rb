# frozen_string_literal: true

FactoryBot.define do
  factory :kanban_api_token do
    account
    sequence(:name) { |n| "Token #{n}" }
    scopes { %w[read:funnels read:tasks write:tasks] }

    # Bypass `generate!` so factory-built tokens are usable in specs
    # WITHOUT needing the raw value. Specs that need authentication via
    # the real digest path should use `KanbanApiToken.generate!(...)`.
    after(:build) do |token|
      raw = "zk_live_#{SecureRandom.urlsafe_base64(24)}"
      token.token_prefix = raw[0, 16]
      token.token_digest = KanbanApiToken.digest_for(raw)
      token.raw_token = raw
    end
  end
end

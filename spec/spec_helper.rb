# Coverage helper must load BEFORE any application code so SimpleCov
# can hook into the Ruby tracer. Gated on COVERAGE=true so day-to-day
# `bundle exec rspec` runs don't slow down with the tracer overhead;
# CI sets the env var explicitly in `univerzap-ci.yml`.
require_relative 'coverage_helper' if ENV['COVERAGE'] == 'true'

require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups

  def with_modified_env(options, &)
    ClimateControl.modify(options, &)
  end
end

# frozen_string_literal: true

# The Message model only mixes in Searchkick when
# `ChatwootApp.advanced_search_allowed?` is truthy AT CLASS-LOAD TIME
# — that check requires both `enterprise?` and an `OPENSEARCH_URL`
# env var. The FOSS CI strips the enterprise tree before the suite
# runs, so Searchkick's `#reindex` macro is never declared and any
# example that fires the `reindex_for_search` after_commit callback
# would otherwise blow up with `NoMethodError`.
#
# We stub the instance method via RSpec mocks on every example so the
# stub survives Zeitwerk reloads between specs (a class-level
# `define_method` in `before(:suite)` gets dropped when the autoloader
# unloads Message). Production behaviour is untouched because there
# Searchkick provides the real implementation and the `next if`
# guard skips the stub entirely.
RSpec.configure do |config|
  config.before(:each) do
    next if defined?(Searchkick) && Message.respond_to?(:searchkick_index)

    # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Message).to receive(:reindex).and_return(true)
    # rubocop:enable RSpec/AnyInstance
  end
end

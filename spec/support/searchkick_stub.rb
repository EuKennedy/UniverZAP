# frozen_string_literal: true

# The Message model only mixes in Searchkick when
# `ChatwootApp.advanced_search_allowed?` is truthy AT CLASS-LOAD TIME
# — that check requires both `enterprise?` and an `OPENSEARCH_URL`
# env var. The FOSS CI strips the enterprise tree before the suite
# runs, so Searchkick's `#reindex` macro is never declared and any
# example that fires the `reindex_for_search` after_commit callback
# would otherwise blow up with `NoMethodError`.
#
# We stub the instance method as a no-op only when Searchkick didn't
# install its own; production behaviour is untouched because there
# Searchkick provides the real implementation.
RSpec.configure do |config|
  config.before(:suite) do
    next if defined?(Searchkick) && Message.respond_to?(:searchkick_index)
    next if Message.method_defined?(:reindex)

    Message.class_eval do
      def reindex(*)
        true
      end
    end
  end
end

# frozen_string_literal: true

# The Message model only mixes in Searchkick when
# `ChatwootApp.advanced_search_allowed?` is truthy AT CLASS-LOAD TIME
# — that check requires both `enterprise?` and an `OPENSEARCH_URL`
# env var. The FOSS CI strips the enterprise tree before the suite
# runs, so Searchkick's `#reindex` macro is never declared and any
# example that fires the `reindex_for_search` after_commit callback
# would otherwise blow up with `NoMethodError`.
#
# We reopen `Message` at spec-support load time (rails_helper requires
# spec/support/**/*.rb once before the suite starts) and define a noop
# `reindex` method ONLY when Searchkick hasn't already installed its
# own. Touching the constant here triggers Rails' autoloader so the
# class is fully defined before we patch it.
#
# Production behaviour is untouched: this file is only required from
# `rails_helper.rb`, never in development or production boot paths.
# Touching `.name` forces Zeitwerk to materialise the constant before we
# patch it; the local binding consumes the value so the file body is
# never just a "void" reference to a constant.
message_class = Message.name && Message
unless message_class.respond_to?(:searchkick_index) || message_class.method_defined?(:reindex)
  message_class.class_eval do
    def reindex(*)
      true
    end
  end
end

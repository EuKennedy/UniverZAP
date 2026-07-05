# The test environment is used exclusively to run your application's
# test suite. You never need to work with it otherwise. Remember that
# your test database is "scratch space" for the test suite and is wiped
# and recreated between test runs. Don't rely on the data there!

require 'active_support/core_ext/integer/time'

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  config.cache_classes = false

  # Eager load the whole app in CI so every constant is loaded once, up front,
  # in a deterministic state — matching how production boots. Locally we keep
  # it off so a single spec runs fast.
  #
  # Why this matters: with lazy loading + reloading enabled (cache_classes
  # false), autoloaded constants can be first-loaded/reloaded in an order that
  # depends on which specs run together. That made `rescue`/`is_a?` checks
  # against constants like Kanban::Automations::Actions::Base::ExecutionError
  # occasionally miss, so the executor suite failed depending only on spec
  # sharding order. Eager loading in CI removes that nondeterminism.
  config.eager_load = ENV['CI'].present?

  # Configure public file server for tests with Cache-Control for performance.
  config.public_file_server.enabled = true
  config.public_file_server.headers = {
    'Cache-Control' => "public, max-age=#{1.hour.to_i}"
  }
  config.action_mailer.default_url_options = { host: 'http://localhost:3000' }
  Rails.application.routes.default_url_options = { host: 'http://localhost:3000' }

  # Show full error reports and disable caching.
  config.consider_all_requests_local       = true
  config.action_controller.perform_caching = false
  config.cache_store = :null_store

  # Raise exceptions instead of rendering exception templates.
  config.action_dispatch.show_exceptions = true

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  # Store uploaded files on the local file system in a temporary directory.
  config.active_storage.service = :test

  config.action_mailer.perform_caching = false

  # Tell Action Mailer not to deliver emails to the real world.
  # The :test delivery method accumulates sent emails in the
  # ActionMailer::Base.deliveries array.
  config.action_mailer.delivery_method = :test
  config.active_job.queue_adapter = :test

  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr

  # Raises error for missing translations.
  # config.action_view.raise_on_missing_translations = true
  config.log_level = ENV.fetch('LOG_LEVEL', 'debug').to_sym
end

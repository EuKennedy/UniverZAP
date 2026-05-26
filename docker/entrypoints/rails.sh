#!/bin/sh

set -x

# Remove a potentially pre-existing server.pid for Rails.
rm -rf /app/tmp/pids/server.pid
rm -rf /app/tmp/cache/*

echo "Waiting for postgres to become ready...."

# Let DATABASE_URL env take presedence over individual connection params.
# This is done to avoid printing the DATABASE_URL in the logs
$(docker/entrypoints/helpers/pg_database_url.rb)
PG_READY="pg_isready -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USERNAME"

until $PG_READY
do
  sleep 2;
done

echo "Database ready to accept connections."

#install missing gems for local dev as we are using base image compiled for production
bundle install

BUNDLE="bundle check"

until $BUNDLE
do
  sleep 2;
done

# Run pending migrations on boot. We rely on Rails' own migration version
# tracking so it's safe even when multiple Rails replicas race the same
# deploy. Set RUN_DB_MIGRATIONS=false to disable per-container (e.g. for
# the Sidekiq replica when running multi-process deploys).
if [ "${RAILS_ENV:-development}" != "development" ] && [ "${RUN_DB_MIGRATIONS:-true}" = "true" ]; then
  echo "Running database migrations (RAILS_ENV=$RAILS_ENV)..."
  bundle exec rails db:migrate || {
    echo "Database migrations failed. Aborting boot.";
    exit 1;
  }
fi

# Execute the main process of the container
exec "$@"

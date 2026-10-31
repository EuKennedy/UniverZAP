# Counts what Conversations::QueueLabelsBackfill would change; APPLY=1 writes it.
#
#   bundle exec rake 'queue_labels:backfill[5]'
#   APPLY=1 bundle exec rake 'queue_labels:backfill[5]'
namespace :queue_labels do
  desc 'Put the stage tags of old conversations in line with what happened in them'
  task :backfill, [:account_id] => :environment do |_t, args|
    apply = ENV['APPLY'] == '1'
    counts = Conversations::QueueLabelsBackfill.new(Account.find(args[:account_id])).perform(apply: apply)

    puts "BACKFILL #{apply ? 'applied' : 'dry run'}: #{counts.inspect}"
  end
end

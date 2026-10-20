# Open conversations that still carry a closing label (atendimento-encerrado,
# cancelado, ficou-inativo…), from before a closing label resolved the
# conversation and before reopening cleared it:
#   - closed last (no message from the contact after the label) → resolved;
#   - the contact wrote after the label → stays open, the stale label goes.
# Silent: columns only, no event, so no automation, CSAT or webhook fires and
# no message reaches a customer.
#
#   bundle exec rake 'encerradas:backfill[5]'
namespace :encerradas do
  desc 'Resolve open conversations closed by a label, drop stale closing labels (silent)'
  task :backfill, [:account_id] => :environment do |_t, args|
    account = Account.find(args[:account_id])
    closing = account.labels.closing.pluck(:title)
    tag_ids = ActsAsTaggableOn::Tag.where(name: closing).pluck(:id)
    resolved = 0
    cleared = 0

    account.conversations.where.not(status: :resolved).tagged_with(closing, on: :labels, any: true).find_each do |conversation|
      taggings = ActsAsTaggableOn::Tagging.where(taggable: conversation, context: 'labels', tag_id: tag_ids)
      closed_at = taggings.maximum(:created_at)
      last_contact = conversation.messages.incoming.where(private: false).maximum(:created_at)

      if last_contact.nil? || last_contact <= closed_at
        conversation.update_columns(status: Conversation.statuses[:resolved], waiting_since: nil) # rubocop:disable Rails/SkipsModelValidations
        resolved += 1
      else
        taggings.delete_all
        remaining = conversation.cached_label_list_array - closing
        conversation.update_columns(cached_label_list: remaining.join(', ')) # rubocop:disable Rails/SkipsModelValidations
        cleared += 1
      end
    end

    puts "Account #{account.id}: #{resolved} conversations resolved; #{cleared} reopened by the contact kept open without the closing label"
  end
end

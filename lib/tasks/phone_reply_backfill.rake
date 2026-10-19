# Recounts, for one account, the replies the WAHA Chatwoot app wrote as
# "📱 Enviado do WhatsApp" private notes before Message#phone_reply_note?
# existed: they never cleared waiting_since or awaiting_reply, so contacts the
# salon had already answered from the phone stayed at the top of Aguardando.
# Only conversations where that note is still the last word are touched.
# Idempotent and silent: columns only, no events, no automation rule fires.
#
#   bundle exec rake phone_reply:backfill[5]
namespace :phone_reply do
  desc 'Count replies typed in the phone WhatsApp (WAHA private notes) as answers on old conversations'
  task :backfill, [:account_id] => :environment do |_t, args|
    account = Account.find(args[:account_id])
    answered = 0

    conversation_ids = account.messages.where(private: true).where("content LIKE '%📱 %WhatsApp%'")
                              .unscope(:order).distinct.pluck(:conversation_id)
    account.conversations.where(id: conversation_ids).find_each do |conversation|
      counted = conversation.messages.where(message_type: [:incoming, :outgoing]).order(:id)
                            .select { |message| !message.private? || message.phone_reply_note? }
      next unless counted.last&.phone_reply_note?

      first_reply = conversation.first_reply_created_at || counted.find(&:phone_reply_note?).created_at
      # rubocop:disable Rails/SkipsModelValidations
      conversation.update_columns(awaiting_reply: false, waiting_since: nil, first_reply_created_at: first_reply)
      # rubocop:enable Rails/SkipsModelValidations
      answered += 1
    end

    puts "Account #{account.id}: #{answered} conversations answered from the phone taken out of Aguardando"
  end
end

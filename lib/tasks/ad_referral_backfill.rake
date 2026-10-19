# Stamps conversations that started from a Click-to-WhatsApp ad BEFORE the
# AdReferralListener existed. Idempotent: a conversation already carrying
# anuncio_id only gets its click counter bumped. No event is fired, so no
# automation rule reassigns or reprioritises old conversations.
#
#   bundle exec rake ad_referral:backfill[5]
namespace :ad_referral do
  desc 'Read the WAHA ad block off old incoming messages and stamp their conversations (no events)'
  task :backfill, [:account_id] => :environment do |_t, args|
    account = Account.find(args[:account_id])
    stamped = 0

    account.messages.incoming
           .where("content ILIKE '%ANÚNCIO DO FACEBOOK%' OR content ILIKE '%FACEBOOK AD%'")
           .order(:id).find_each do |message|
      next if message.content_attributes['ad_referral'].present?

      Conversations::AdReferralService.new(message, silent: true).perform
      stamped += 1
    end

    puts "Account #{account.id}: #{stamped} ad messages stamped; " \
         "#{account.conversations.where("jsonb_exists(custom_attributes, 'anuncio_id')").count} conversations carry anuncio_id"
  end
end

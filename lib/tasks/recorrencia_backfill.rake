# Marks returning customers that existed BEFORE RecurringCustomerListener did,
# and fills the origin of contacts that never went through
# ContactOriginListener. Idempotent and silent: no event fires, so no
# automation rule reassigns or reprioritises old conversations.
#
# Both shapes of a return count (Conversations::RecurringCustomerService):
# a second conversation after one that ended, and the same conversation
# resolved before and reopened by a later message from the contact (the WAHA
# bridge keeps one conversation per contact). Open conversations get the
# label; a conversation already resolved again only stamps its contact.
#
#   bundle exec rake recorrencia:backfill[5]
namespace :recorrencia do
  desc 'Label open conversations of returning customers and stamp recorrente / origem_lead on contacts (no events)'
  task :backfill, [:account_id] => :environment do |_t, args|
    account = Account.find(args[:account_id])
    label = Conversations::RecurringCustomerService.label_for(account)
    abort "Account #{account.id}: its vertical has no returning-customer label" if label.blank?

    labelled = 0
    recurring = 0
    origins = Hash.new(0)

    account.conversations.where.not(status: :resolved).find_each do |conversation|
      next if conversation.label_list.include?(label)
      next unless Conversations::RecurringCustomerService.recurring?(conversation)

      already = conversation.contact.custom_attributes[Conversations::RecurringCustomerService::ATTRIBUTE] == true
      Conversations::RecurringCustomerService.new(conversation, silent: true).perform
      labelled += 1
      recurring += 1 unless already
    end

    account.contacts.find_each do |contact|
      latest = contact.conversations.reorder(:created_at).last
      next if latest.nil?

      origin = Contacts::OriginService.new(contact).perform
      origins[origin] += 1 if origin
      next unless Conversations::RecurringCustomerService.recurring?(latest)

      recurring += 1 if Conversations::RecurringCustomerService.new(latest, silent: true).stamp_contact
    end

    breakdown = origins.map { |origin, count| "#{origin}: #{count}" }.join(', ')
    puts "Account #{account.id}: #{labelled} open conversations labelled #{label}; " \
         "#{recurring} contacts stamped recorrente; origem_lead filled on #{origins.values.sum} contacts (#{breakdown})"
  end
end

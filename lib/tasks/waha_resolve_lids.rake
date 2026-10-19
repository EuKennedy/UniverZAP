# Resolve, numa conta, os contatos que a ponte WAHA criou só com o LID
# (identifier "…@lid", sem telefone): pergunta o número à sessão WAHA da
# caixa, grava phone_number e waha_whatsapp_jid, mescla num contato que já
# tenha o número e, quando a WAHA ainda não conhece o número, troca o nome
# "159…@lid" pelo pushName ou por "Contato sem número". Idempotente.
#
#   bundle exec rake waha:resolve_lids[5]
namespace :waha do
  desc 'Resolve LID-only contacts of an account to phone numbers through the WAHA lids API'
  task :resolve_lids, [:account_id] => :environment do |_t, args|
    account = Account.find(args[:account_id])
    totals = Hash.new(0)

    account.contacts.where("identifier LIKE '%@lid'").where(phone_number: [nil, '']).find_each do |contact|
      totals[Whatsapp::WahaLidResolver.new(contact).perform] += 1
    rescue StandardError => e
      totals[:failed] += 1
      puts "contact #{contact.id} (#{contact.identifier}): #{e.class}: #{e.message}"
    end

    puts "Account #{account.id}: #{totals[:resolved]} resolved, #{totals[:merged]} merged into an existing contact, " \
         "#{totals[:unresolved]} still without a number, #{totals[:skipped]} skipped, #{totals[:failed]} failed"
  end
end

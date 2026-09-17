# Re-sincroniza o Guia com o /docs. Roda depois de editar o manual: sem isto o
# agente segue respondendo a versão anterior da documentação, e ninguém percebe
# porque a resposta continua saindo com confiança.
namespace :ai do
  namespace :wiki do
    desc 'Cria/atualiza o agente Guia e o conhecimento dele a partir de /docs (todas as contas)'
    task sync: :environment do
      total = Account.count
      Account.find_each.with_index(1) do |account, index|
        Ai::Wiki::Seeder.new(account: account).perform
        puts "[#{index}/#{total}] conta #{account.id} sincronizada"
      rescue StandardError => e
        warn "[#{index}/#{total}] conta #{account.id} FALHOU: #{e.message}"
      end
      puts "seções lidas do manual: #{Ai::Wiki::Manual.sections.size}"
    end
  end
end

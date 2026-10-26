# Leva os anexos que estão no disco da VPS para o Cloudflare R2
# (Storage::BlobMigration). Pode rodar com o sistema no ar e mais de uma vez:
# o que já foi copiado é pulado. Rodar depois de trocar
# ACTIVE_STORAGE_SERVICE para cloudflare, para não sobrar anexo novo no disco.
#
#   bundle exec rake storage:migrate_to_r2
#   nohup bundle exec rake storage:migrate_to_r2 > log/r2_migration.log 2>&1 &
namespace :storage do
  desc 'Copy ActiveStorage files from local disk to Cloudflare R2 and repoint their blobs'
  task migrate_to_r2: :environment do
    Storage::BlobMigration.new.perform!
  end
end

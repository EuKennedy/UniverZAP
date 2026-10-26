# Copia os arquivos do ActiveStorage de um serviço para outro (por padrão do
# disco da VPS, `local`, para o Cloudflare R2, `cloudflare`) e aponta cada
# blob para o destino. Cada blob guarda o próprio service_name, então o que já
# migrou passa a sair do R2 e o resto continua saindo do disco: dá para rodar
# com o sistema no ar, parar no meio e rodar de novo.
#
# Não apaga nada da origem. Os arquivos do disco só saem depois de conferir
# que tudo abre pelo R2 (`lib/tasks/storage.rake`).
class Storage::BlobMigration
  def initialize(from: 'local', to: 'cloudflare', out: $stdout)
    @from = from
    @to = to
    @out = out
    @totals = Hash.new(0)
  end

  def perform!
    pending = ActiveStorage::Blob.where(service_name: @from)
    @out.puts("#{pending.count} arquivos em #{@from} para copiar para #{@to}")
    pending.find_each { |blob| migrate(blob) }
    @out.puts("copiados: #{@totals[:copied]}, já estavam no destino: #{@totals[:present]}, " \
              "sem arquivo na origem: #{@totals[:missing]}, falharam: #{@totals[:failed]}")
  end

  private

  def migrate(blob)
    result = copy(blob)
    # Sem o arquivo na origem não há o que levar: o blob fica onde está.
    # update_columns de propósito: só muda onde o arquivo mora, sem tocar
    # updated_at nem disparar o touch nos anexos e mensagens de cada blob.
    # rubocop:disable Rails/SkipsModelValidations
    blob.update_columns(service_name: @to) unless result == :missing
    # rubocop:enable Rails/SkipsModelValidations
    @totals[result] += 1
    progress
  rescue StandardError => e
    @totals[:failed] += 1
    @out.puts("blob #{blob.id} (#{blob.key}): #{e.class}: #{e.message}")
  end

  def copy(blob)
    return :present if target.exist?(blob.key)
    return :missing unless source.exist?(blob.key)

    source.open(blob.key, checksum: blob.checksum, verify: blob.checksum.present?) do |file|
      target.upload(blob.key, file, checksum: blob.checksum, content_type: blob.content_type, filename: blob.filename)
    end
    :copied
  end

  def progress
    done = @totals.values.sum
    @out.puts("... #{done}") if (done % 500).zero?
  end

  def source
    @source ||= ActiveStorage::Blob.services.fetch(@from)
  end

  def target
    @target ||= ActiveStorage::Blob.services.fetch(@to)
  end
end

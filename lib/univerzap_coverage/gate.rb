# frozen_string_literal: true

require 'json'

# Soma os resultsets dos 8 shards de RSpec e diz se o código nosso está acima
# do piso.
#
# ## Por que somar na mão em vez de usar SimpleCov.collate
#
# Duas razões concretas, as duas já vividas nesta base:
#
#   1. O `collate` descarta resultado mais velho que `merge_timeout` (10 min
#      por padrão). Nossa matriz tem shards que terminam com meia hora de
#      diferença, então o merge jogaria fora os primeiros e reportaria menos
#      cobertura do que a real, em silêncio, sem erro nenhum.
#   2. O formato do resultset é estável e trivial; a API interna do SimpleCov
#      não é. Um portão que segura deploy não pode quebrar por refactor de
#      dependência.
#
# ## O que o percentual significa
#
# Linhas relevantes: `nil` no array é linha que não executa (comentário, `end`,
# linha em branco) e não entra na conta. Zero é linha executável que ninguém
# rodou. Então 80% aqui é "8 de cada 10 linhas que rodam foram rodadas por
# algum teste", e não uma proporção do arquivo.
class UniverzapCoverage::Gate
  Row = Struct.new(:relevant, :covered, :files, :uncovered) do
    def percent
      return nil if relevant.zero?

      (covered.to_f / relevant * 100).round(2)
    end
  end

  attr_reader :coverage, :floors

  # @param coverage [Hash] caminho do arquivo => array de contagem por linha
  # @param floors [Hash] nome do grupo => piso em porcentagem
  def initialize(coverage, floors: {})
    @coverage = coverage
    @floors = floors || {}
  end

  def self.from_dir(dir, floors: {})
    files = Dir.glob(File.join(dir, '**', '.resultset.json'))
    raise ArgumentError, "nenhum .resultset.json em #{dir}" if files.empty?

    new(merge(files.map { |file| read(file) }), floors: floors)
  end

  def self.read(file)
    parsed = JSON.parse(File.read(file))
    # { "RSpec" => { "coverage" => { path => {"lines" => [...]} | [...] } } }
    parsed.values.each_with_object({}) do |suite, out|
      (suite['coverage'] || {}).each { |path, entry| out[path] = lines_of(entry) }
    end
  rescue JSON::ParserError
    {}
  end

  # O formato mudou entre versões do SimpleCov: antes o valor era o array de
  # linhas direto, hoje é um hash com "lines" (e "branches", que ignoramos).
  def self.lines_of(entry)
    entry.is_a?(Hash) ? entry['lines'] : entry
  end

  def self.merge(coverages)
    coverages.each_with_object({}) do |coverage, merged|
      coverage.each do |path, lines|
        merged[path] = merge_lines(merged[path], lines)
      end
    end
  end

  # `nil` numa posição quer dizer "linha não executável", e só vence quando os
  # dois lados são nil: se um shard carregou o arquivo e o outro nem chegou
  # nele, quem viu a linha manda.
  def self.merge_lines(left, right)
    return right if left.nil?
    return left if right.nil?

    Array.new([left.length, right.length].max) do |index|
      a = left[index]
      b = right[index]
      a.nil? && b.nil? ? nil : a.to_i + b.to_i
    end
  end

  def report
    @report ||= build_report
  end

  def total
    Row.new(
      report.values.sum(&:relevant),
      report.values.sum(&:covered),
      report.values.sum(&:files),
      []
    )
  end

  # Vazio quando passa. Grupo sem piso declarado nunca reprova: exigir número
  # de algo que nunca foi medido é escolher no chute.
  def failures
    report.filter_map do |name, row|
      floor = floors[name]
      next if floor.nil? || row.percent.nil? || row.percent >= floor

      "#{name}: #{row.percent}% abaixo do piso de #{floor}%"
    end
  end

  # Nada nosso medido é erro de encanamento, não aprovação. Já aconteceu de o
  # artefato subir sem o resultset e a build ficar verde sem medir nada.
  def measured_nothing?
    total.relevant.zero?
  end

  private

  def build_report
    # rubocop:disable Rails/IndexWith
    # `index_with` é ActiveSupport, e este arquivo precisa rodar sem ele: o
    # job de cobertura chama bin/coverage_gate.rb com `bundler-cache: false`,
    # sem Rails e sem gem nenhuma instalada, justamente para não gastar
    # minutos montando o Gemfile inteiro só para somar oito JSON. Trocar por
    # index_with aqui deixa o portão verde no RuboCop e morto na execução.
    blank = UniverzapCoverage::GROUPS.keys.to_h { |name| [name, Row.new(0, 0, 0, [])] }
    # rubocop:enable Rails/IndexWith
    coverage.each_with_object(blank) do |(path, lines), out|
      group = UniverzapCoverage.group_for(path)
      next unless group

      accumulate(out[group], path, lines)
    end
  end

  def accumulate(row, path, lines)
    relevant = Array(lines).compact
    covered = relevant.count(&:positive?)
    row.relevant += relevant.length
    row.covered += covered
    row.files += 1
    row.uncovered << path if relevant.any? && covered.zero?
  end
end

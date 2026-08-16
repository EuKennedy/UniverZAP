#!/usr/bin/env ruby
# frozen_string_literal: true

# Roda o portão de cobertura sobre os shards baixados pela CI.
#
# Fino de propósito: toda a lógica mora em UniverZAP::Gate, que tem spec
# próprio rodando junto com o resto da suíte. Um script que decide se o deploy
# sai não pode ser a única coisa no repositório sem teste.
#
#   ruby bin/coverage_gate.rb coverage_shards

require 'yaml'
require_relative '../lib/univerzap_coverage'
require_relative '../lib/univerzap_coverage/gate'

shard_dir = ARGV[0] || 'coverage_shards'
floors_file = File.expand_path('../config/coverage_floors.yml', __dir__)

floors =
  begin
    File.exist?(floors_file) ? (YAML.safe_load(File.read(floors_file)) || {}) : {}
  rescue Psych::SyntaxError => e
    abort("ERRO: config/coverage_floors.yml invalido: #{e.message}")
  end

gate =
  begin
    UniverzapCoverage::Gate.from_dir(shard_dir, floors: floors)
  rescue ArgumentError => e
    abort("ERRO: #{e.message}. O artefato subiu sem os arquivos ocultos?")
  end

puts
puts 'Cobertura do codigo UniverZAP (o fork nao entra na conta):'
gate.report.each do |name, row|
  measured = row.percent ? format('%6.2f%%', row.percent) : '     --'
  target = floors[name] ? format('piso %.2f%%', floors[name]) : 'sem piso'
  # Tudo posicional. Misturar `%-20s` com `%<pct>s` no mesmo format levanta
  # "named after unnumbered", que foi como este script morreu na estreia.
  puts format('  %-20s %s  (%5d linhas em %3d arquivos)  %s',
              name, measured, row.relevant, row.files, target)
end

total = gate.total
puts format('  %-20s %6.2f%%  (%5d linhas)', 'TOTAL', total.percent || 0, total.relevant)

untested = gate.report.values.flat_map(&:uncovered).sort
if untested.any?
  puts
  puts "Arquivos nossos sem NENHUMA linha coberta (#{untested.length}):"
  untested.first(40).each { |path| puts "  - #{path.split(%r{/app/}).last}" }
  puts "  ... e mais #{untested.length - 40}" if untested.length > 40
end

abort("\nERRO: nenhuma linha nossa foi medida. Os caminhos em lib/univerzap_coverage.rb ainda existem?") if gate.measured_nothing?

failures = gate.failures
unless failures.empty?
  puts
  puts 'REPROVADO:'
  failures.each { |line| puts "  - #{line}" }
  exit 1
end

puts
puts floors.empty? ? 'Sem pisos declarados ainda: rodada apenas informativa.' : 'Todos os pisos atendidos.'

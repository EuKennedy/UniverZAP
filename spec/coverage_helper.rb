require 'simplecov'
require 'simplecov_json_formatter'
# Caminho relativo e não `require 'univerzap_coverage'`: isto roda antes de
# qualquer código de aplicação, então o autoload do Rails e o $LOAD_PATH dele
# ainda não existem.
require_relative '../lib/univerzap_coverage'

# Emit BOTH HTML (for the artifact uploaded by CI) and JSON (Qlty + any
# future automated coverage reporter). Filters concentrate the report
# on app code — vendor / bin / specs themselves are noise.
SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new(
  [
    SimpleCov::Formatter::SimpleFormatter,
    SimpleCov::Formatter::JSONFormatter
  ]
)
SimpleCov.start 'rails' do
  coverage_dir 'coverage'
  add_filter '/spec/'
  add_filter '/config/'
  add_filter '/db/'
  add_filter '/vendor/'
  add_filter '/bin/'

  # Os módulos que são nossos, separados do fork.
  #
  # Um número único para este repositório mede sobretudo o Chatwoot, que tem
  # cobertura própria e que a gente não escreveu, então ele sobe e desce por
  # motivos que não são decisão de ninguém aqui. Estes grupos existem para que
  # o portão de cobertura (bin/coverage_gate.rb) possa exigir um piso do
  # código que a gente de fato mantém, e a lista de caminhos é a MESMA nos dois
  # lugares: se divergir, o relatório e o portão passam a falar de conjuntos
  # diferentes sem ninguém perceber.
  UniverzapCoverage::GROUPS.each do |name, paths|
    add_group(name) { |src| UniverzapCoverage.owned_by?(src.filename, paths) }
  end

  # Sem mínimo aqui de propósito. O portão roda depois, sobre os 8 shards
  # colados: cada shard sozinho enxerga uma fatia do código e reprovaria por
  # arquivos que outro shard cobriu.
end

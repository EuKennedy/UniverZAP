# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'
require 'open3'

RSpec.describe UniverzapCoverage::Gate do
  # Um caminho que o portão reconhece como nosso e outro que ele tem que
  # ignorar. Se estes deixarem de bater com lib/univerzap_coverage.rb, é aqui
  # que o desencontro aparece, e não em produção medindo o conjunto errado.
  let(:ours) { '/home/runner/work/app/services/ai/reports/period.rb' }
  let(:upstream) { '/home/runner/work/app/services/filter_service.rb' }

  # A cobertura de um arquivo só, que é do que cada exemplo daqui precisa.
  #
  # O caminho vem separado do array de propósito. Escrito como
  # `gate(ours => [1, 1, 0])`, o Ruby 3 lê o hash pelado como argumento
  # NOMEADO, porque este método tem um, e o exemplo morre com "wrong number of
  # arguments" sem ter testado coisa alguma. Dois parâmetros posicionais tiram
  # a armadilha do caminho em vez de exigir que a próxima pessoa lembre das
  # chaves.
  def gate(path, lines, floors: {})
    described_class.new({ path => lines }, floors: floors)
  end

  describe 'somar os shards' do
    # Cada shard roda um oitavo dos specs, então o mesmo arquivo aparece em
    # vários resultsets com contagens diferentes. Somar errado aqui subestima
    # a cobertura e reprova gente que não quebrou nada.
    it 'soma a mesma linha vista por shards diferentes' do
      merged = described_class.merge([{ ours => [1, 0, 3] }, { ours => [2, 0, 0] }])

      expect(merged[ours]).to eq([3, 0, 3])
    end

    # nil é linha que não executa: comentário, `end`, linha em branco. Virar
    # zero faria o denominador crescer e derrubaria o percentual de todo mundo.
    it 'mantem como nao executavel a linha que nenhum shard considerou codigo' do
      merged = described_class.merge([{ ours => [1, nil] }, { ours => [1, nil] }])

      expect(merged[ours]).to eq([2, nil])
    end

    # Um shard que nem carregou o arquivo devolve nil onde o outro devolveu
    # número. Quem enxergou a linha manda.
    it 'aceita o lado que enxergou a linha quando o outro nao carregou o arquivo' do
      merged = described_class.merge([{ ours => [nil, nil] }, { ours => [4, 0] }])

      expect(merged[ours]).to eq([4, 0])
    end

    it 'junta arquivos que so aparecem em um dos shards' do
      merged = described_class.merge([{ ours => [1] }, { upstream => [1] }])

      expect(merged.keys).to contain_exactly(ours, upstream)
    end
  end

  describe 'o que conta como codigo nosso' do
    it 'atribui o arquivo ao grupo dele' do
      report = gate(ours, [1, 1, 0]).report

      expect(report['Athenas (IA)'].files).to eq(1)
      expect(report['Athenas (IA)'].relevant).to eq(3)
    end

    # O fork tem cobertura própria, escrita por outra gente, e sobe ou desce
    # por decisão que não é nossa. Exigir piso dele seria travar nosso deploy
    # por causa do Chatwoot.
    it 'ignora arquivo do fork' do
      expect(gate(upstream, [0, 0, 0])).to be_measured_nothing
    end
  end

  describe 'o percentual' do
    it 'conta apenas linhas executaveis' do
      # 4 relevantes, 3 rodadas: os dois nil não entram no denominador.
      expect(gate(ours, [1, 0, nil, 2, nil, 5]).report['Athenas (IA)'].percent).to eq(75.0)
    end

    it 'fica vazio em vez de zero quando nao ha linha relevante' do
      expect(gate(ours, [nil, nil]).report['Athenas (IA)'].percent).to be_nil
    end

    it 'soma os grupos no total' do
      total = gate(ours, [1, 0]).total

      expect(total.relevant).to eq(2)
      expect(total.percent).to eq(50.0)
    end
  end

  describe 'o veredito' do
    it 'reprova o grupo abaixo do piso declarado' do
      failing = gate(ours, [1, 0, 0, 0], floors: { 'Athenas (IA)' => 80.0 })

      expect(failing.failures.first).to include('Athenas (IA)', '25.0%', '80.0%')
    end

    it 'aprova o grupo acima do piso' do
      passing = gate(ours, [1, 1, 1, 0], floors: { 'Athenas (IA)' => 70.0 })

      expect(passing.failures).to be_empty
    end

    # Exigir número de algo que nunca foi medido é escolher no chute e depois
    # conviver com a escolha.
    it 'nunca reprova grupo sem piso declarado' do
      expect(gate(ours, [0, 0, 0]).failures).to be_empty
    end
  end

  describe 'ler os resultsets do disco' do
    let(:dir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(dir) }

    def write_resultset(name, coverage)
      shard = File.join(dir, name)
      FileUtils.mkdir_p(shard)
      File.write(File.join(shard, '.resultset.json'),
                 { 'RSpec' => { 'coverage' => coverage, 'timestamp' => 1 } }.to_json)
    end

    # Um artefato vazio já aconteceu de verdade: o upload-artifact descarta
    # arquivo oculto por padrão e o resultset nunca chegou. A build ficava
    # verde sem ter medido nada, que é pior do que ficar vermelha.
    it 'recusa uma pasta sem nenhum resultset' do
      expect { described_class.from_dir(dir) }.to raise_error(ArgumentError, /nenhum/)
    end

    it 'soma resultsets de shards diferentes' do
      write_resultset('backend-coverage-0', { ours => { 'lines' => [1, 0] } })
      write_resultset('backend-coverage-1', { ours => { 'lines' => [0, 1] } })

      expect(described_class.from_dir(dir).report['Athenas (IA)'].percent).to eq(100.0)
    end

    # SimpleCov mais antigo gravava o array direto no lugar do hash com
    # "lines". Ler só o formato novo devolveria zero sem avisar.
    it 'entende o formato antigo em que o valor era o array de linhas' do
      write_resultset('backend-coverage-0', { ours => [1, 1] })

      expect(described_class.from_dir(dir).report['Athenas (IA)'].covered).to eq(2)
    end

    it 'ignora um resultset corrompido em vez de derrubar o portao' do
      write_resultset('backend-coverage-0', { ours => { 'lines' => [1] } })
      FileUtils.mkdir_p(File.join(dir, 'backend-coverage-1'))
      File.write(File.join(dir, 'backend-coverage-1', '.resultset.json'), '{ nao e json')

      expect(described_class.from_dir(dir).report['Athenas (IA)'].covered).to eq(1)
    end

    # O executável, rodado do mesmo jeito que a CI roda.
    #
    # Os 14 exemplos acima cobrem a classe inteira e mesmo assim o portão
    # morreu na estreia, com ArgumentError na PRIMEIRA linha impressa: o
    # `format` do Ruby não aceita `%-20s` posicional junto de `%<pct>s`
    # nomeado. Nenhum teste da classe podia pegar aquilo, porque o defeito
    # estava na casca e não no miolo. Um script que decide se o deploy sai
    # precisa ser executado por algum teste, e não só lido.
    it 'roda de ponta a ponta e imprime o relatorio' do
      write_resultset('backend-coverage-0', { ours => { 'lines' => [1, 0] } })

      out, err, status = Open3.capture3('ruby', Rails.root.join('bin/coverage_gate.rb').to_s, dir)

      expect(status).to be_success, err
      expect(out).to include('Athenas (IA)', 'TOTAL', '50.00%')
    end
  end
end

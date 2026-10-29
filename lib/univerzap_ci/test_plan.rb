# frozen_string_literal: true

# Decide o que a CI roda a partir dos arquivos que o PR (ou o push) mudou:
# os specs do que foi mexido, os testes de front que dependem dos arquivos
# alterados e o lint só desses arquivos. Mexer no armário do almoxarifado não
# testa o micro-ondas da cozinha.
#
# Um spec entra quando:
#   - ele mesmo mudou;
#   - é o espelho do arquivo (app/services/a/b.rb -> spec/services/a/b_spec.rb);
#   - cita a constante do arquivo (Woocommerce::Client, StoreOrder...);
#   - num model, monta a factory dele (create(:store_order...)), que é como a
#     maioria dos specs usa Account, Contact e companhia sem citar a classe.
# Uma view puxa os specs do controller dela.
#
# O que sustenta a suíte inteira (Gemfile, helpers e factories de spec,
# configuração, o próprio CI) roda tudo: ali não dá para saber quem depende
# de quê. A rede de segurança é a suíte completa todo dia (schedule) e o
# botão manual com full.
#
# Sem Rails nem gem: roda no job que monta o plano, antes de qualquer bundle.
module UniverzapCi
  class TestPlan
    FULL_SUITE = [
      'Gemfile', 'Gemfile.lock', '.ruby-version', '.rubocop.yml',
      'package.json', 'pnpm-lock.yaml', '.nvmrc', '.eslintrc.js', 'vite.config.ts', 'vitest.setup.js',
      '.github/workflows/univerzap-ci.yml', 'bin/ci_test_plan.rb',
      %r{\Alib/univerzap_ci/},
      %r{\Aspec/(rails_helper|spec_helper|coverage_helper)\.rb\z}, %r{\Aspec/(support|factories)/},
      %r{\Aconfig/(application|boot|environment|database|storage)\.rb\z}, %r{\Aconfig/(environments|initializers)/},
      %r{\Aapp/(models/application_record|controllers/application_controller|jobs/application_job)\.rb\z},
      'app/controllers/api/v1/accounts/base_controller.rb'
    ].freeze

    # Diretórios cujo conteúdo é a raiz das constantes (Zeitwerk).
    ROOTS = %r{\A(?:enterprise/)?app/(?:[^/]+/concerns|[^/]+)/|\A(?:enterprise/)?lib/}
    JS = %r{\Aapp/javascript/.+\.(?:js|vue|json|ts)\z}
    RUBY = /(?:\.rb|\.rake|\AGemfile)\z/

    attr_reader :changed

    # changed: caminhos que mudaram (inclui apagados). specs: todos os
    # *_spec.rb do repositório. read: como ler um spec (troca nos testes);
    # binread porque a CI pode rodar sem locale UTF-8 e as constantes são ASCII.
    def initialize(changed, specs:, read: ->(path) { File.binread(path) }, exists: ->(path) { File.exist?(path) })
      @changed = changed.uniq
      @specs = specs
      @read = read
      @exists = exists
    end

    def full?
      @changed.any? { |path| FULL_SUITE.any? { |rule| rule.is_a?(Regexp) ? rule.match?(path) : rule == path } }
    end

    def rspec
      (changed_specs + mirror_specs + citing_specs).uniq.sort
    end

    def vitest
      present(@changed.grep(JS))
    end

    def rubocop
      present(@changed.grep(RUBY))
    end

    def eslint
      present(@changed.grep(%r{\Aapp/.+\.(?:js|vue)\z}))
    end

    private

    def present(paths)
      paths.select { |path| @exists.call(path) }.sort
    end

    def changed_specs
      present(@changed.grep(/_spec\.rb\z/))
    end

    def code
      @changed.grep(/\.rb\z/).grep_v(/_spec\.rb\z/).grep(ROOTS)
    end

    def mirror_specs
      code.filter_map do |path|
        spec = path.sub(%r{\A(enterprise/)?app/}, '\1spec/').sub(%r{\A(enterprise/)?lib/}, '\1spec/lib/')
        spec = "spec/enterprise/#{spec.delete_prefix('enterprise/spec/')}" if spec.start_with?('enterprise/spec/')
        spec = spec.sub(/\.rb\z/, '_spec.rb')
        spec if @specs.include?(spec)
      end
    end

    def citing_specs
      constants = (code.map { |path| constant(path) } + view_controllers).uniq.map { |name| Regexp.escape(name) }
      factories = code.grep(%r{\Aapp/models/[^/]+\.rb\z}).map { |path| Regexp.escape(File.basename(path, '.rb')) }
      return [] if constants.empty?

      pattern = /\b(?:#{constants.join('|')})\b/
      pattern = Regexp.union(pattern, /\b(?:create|build|build_stubbed|create_list|build_list)\(:(?:#{factories.join('|')})\b/) if factories.any?
      @specs.select { |spec| pattern.match?(@read.call(spec)) }
    end

    def constant(path)
      path.sub(ROOTS, '').delete_suffix('.rb').split('/').map { |part| camelize(part) }.join('::')
    end

    # app/views/super_admin/accounts/show.html.erb -> SuperAdmin::AccountsController
    def view_controllers
      @changed.grep(%r{\Aapp/views/(.+)/[^/]+\z}) { Regexp.last_match(1) }
              .reject { |dir| dir.start_with?('layouts', 'shared', 'mailers') }
              .map { |dir| "#{dir.split('/').map { |part| camelize(part) }.join('::')}Controller" }
    end

    def camelize(part)
      part.split('_').map(&:capitalize).join
    end
  end
end

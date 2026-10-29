#!/usr/bin/env ruby
# frozen_string_literal: true

# Monta o plano de testes da CI e escreve em $GITHUB_OUTPUT.
#
#   ruby bin/ci_test_plan.rb <base-sha> [full]
#
# Fino de propósito: a decisão mora em UniverzapCi::TestPlan, que tem spec.
# Cada saída é uma lista separada por espaço, ou ALL para rodar tudo, ou
# vazia para pular o job.

require 'json'
require_relative '../lib/univerzap_ci/test_plan'

base = ARGV[0].to_s
forced = ARGV[1] == 'full'

changed = `git diff --name-only --no-renames #{base} HEAD`.split("\n")
abort("ERRO: git diff contra #{base} falhou") unless $?.success? # rubocop:disable Style/SpecialGlobalVars

plan = UniverzapCi::TestPlan.new(changed, specs: Dir.glob('spec/**/*_spec.rb') + Dir.glob('enterprise/spec/**/*_spec.rb'))
full = forced || plan.full?

outputs = {
  'full' => full.to_s,
  'rspec' => full ? 'ALL' : plan.rspec.join(' '),
  'vitest' => full ? 'ALL' : plan.vitest.join(' '),
  'rubocop' => full ? 'ALL' : plan.rubocop.join(' '),
  'eslint' => full ? 'ALL' : plan.eslint.join(' ')
}
# A suíte inteira vai em 8 máquinas. Poucos specs cabem em uma: subir banco
# e dependências em oito para rodar cinco arquivos era o desperdício.
nodes = full ? 8 : [[(plan.rspec.size / 60.0).ceil, 1].max, 4].min
outputs['rspec_matrix'] = JSON.generate('ci_node_total' => [nodes], 'ci_node_index' => (0...nodes).to_a)

puts "Base: #{base} | arquivos mudados: #{changed.size} | suíte completa: #{full}"
%w[rspec vitest rubocop eslint].each do |key|
  list = outputs[key].split
  puts "#{key}: #{list.empty? ? 'nada' : list.size}"
  list.first(40).each { |path| puts "  #{path}" } unless full
end

File.open(ENV.fetch('GITHUB_OUTPUT', File::NULL), 'a') do |out|
  outputs.each { |key, value| out.puts("#{key}=#{value}") }
end

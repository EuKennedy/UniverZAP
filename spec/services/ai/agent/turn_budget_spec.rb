require 'rails_helper'

RSpec.describe Ai::Agent::TurnBudget do
  def response(cents, input: 1000, output: 200)
    invocation = instance_double(
      Ai::Invocation, cost_brl: cents / 100.0, input_tokens: input, output_tokens: output
    )
    { invocation: invocation }
  end

  it 'nasce com tudo disponível' do
    budget = described_class.new

    expect(budget.exhausted?).to be(false)
    expect(budget.spent_cents).to eq(0)
    expect(budget.spent_tokens).to eq([0, 0])
  end

  # Um turno com ferramenta são várias chamadas, e o preço é a soma delas.
  it 'soma o gasto e os tokens de cada chamada' do
    budget = described_class.new
    budget.charge(response(120))
    budget.charge(response(80, input: 500, output: 50))

    expect(budget.spent_cents).to eq(200)
    expect(budget.spent_tokens).to eq([1500, 250])
  end

  # Uma chamada que falhou não gerou linha de log e não tem custo a cobrar.
  it 'ignora resposta sem invocação, em vez de estourar' do
    budget = described_class.new

    expect { budget.charge({ content: 'oi' }) }.not_to raise_error
    expect(budget.charge(nil)).to be_nil
    expect(budget.spent_cents).to eq(0)
  end

  it 'esgota quando o dinheiro acaba' do
    budget = described_class.new(max_cents: 100)
    budget.charge(response(100))

    expect(budget).to be_exhausted
    expect(budget.reason).to eq('dinheiro')
  end

  it 'esgota quando o tempo acaba' do
    budget = described_class.new(seconds: -1)

    expect(budget).to be_exhausted
    expect(budget.reason).to eq('tempo')
  end

  # "Demorou" e "ficou caro" pedem providências diferentes de quem olhar o log.
  it 'não dá motivo enquanto há orçamento' do
    expect(described_class.new.reason).to be_nil
  end

  it 'deixa passar o turno que ficou logo abaixo do teto' do
    budget = described_class.new(max_cents: 100)
    budget.charge(response(99))

    expect(budget).not_to be_exhausted
  end
end

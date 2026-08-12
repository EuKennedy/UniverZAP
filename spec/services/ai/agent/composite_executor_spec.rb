require 'rails_helper'

RSpec.describe Ai::Agent::CompositeExecutor do
  subject(:executor) do
    described_class.new([[cart_definitions, cart], [agenda_definitions, agenda]])
  end

  let(:cart) { double('cart executor', performed_write?: false) } # rubocop:disable RSpec/VerifiedDoubles
  let(:agenda) { double('agenda executor', performed_write?: false) } # rubocop:disable RSpec/VerifiedDoubles
  let(:cart_definitions) { [{ name: 'montar_carrinho' }] }
  let(:agenda_definitions) { [{ name: 'consultar_horarios' }, { name: 'agendar' }] }

  # The reason this class exists: a salon sells products AND books chairs, and
  # before it the router picked one, so an agent with a cart tool could never
  # reach its agenda.
  it 'offers every tool from every part, in order' do
    expect(executor.definitions.map { |d| d[:name] })
      .to eq(%w[montar_carrinho consultar_horarios agendar])
  end

  it 'routes a call to the part that owns the name' do
    allow(agenda).to receive(:call).with('agendar', { 'inicio' => 'x' }).and_return('{"agendado":true}')

    expect(executor.call('agendar', { 'inicio' => 'x' })).to eq('{"agendado":true}')
    expect(agenda).to have_received(:call)
  end

  it 'never sends a name to the wrong part' do
    allow(cart).to receive(:call).and_return('{}')
    allow(agenda).to receive(:call).and_return('{}')

    executor.call('montar_carrinho', {})

    expect(agenda).not_to have_received(:call)
  end

  it 'reports an unknown tool as data instead of raising' do
    expect(JSON.parse(executor.call('inexistente', {}))).to include('error' => true)
  end

  # A single booking makes the whole turn non-replayable, not only the last
  # tool that ran.
  it 'is written once any part has written' do
    allow(agenda).to receive(:performed_write?).and_return(true)

    expect(executor).to be_performed_write
  end

  it 'is not written when nobody wrote' do
    expect(executor).not_to be_performed_write
  end

  it 'ignores a part with no definitions rather than shadowing names' do
    only_cart = described_class.new([[cart_definitions, cart], [nil, agenda]])

    expect(only_cart.definitions.map { |d| d[:name] }).to eq(['montar_carrinho'])
  end
end

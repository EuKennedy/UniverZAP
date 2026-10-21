require 'rails_helper'

RSpec.describe Chatflow::ConditionEvaluator do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, custom_attributes: { 'origem_lead' => 'anuncio_facebook', 'pontos' => '12' }) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, custom_attributes: { 'servico' => 'Escova' }) }
  let!(:vip) { create(:label, account: account, title: 'vip') }

  def evaluate(rules, match: 'all', now: Time.current)
    described_class.new(conversation, { 'match' => match, 'rules' => rules }, now: now).handle
  end

  it 'sem regras segue pelo verdadeiro' do
    expect(evaluate([])).to eq('true')
  end

  it 'etiqueta tem / não tem' do
    conversation.update_labels(['vip'])
    expect(evaluate([{ 'type' => 'label', 'operator' => 'has', 'label_ids' => [vip.id] }])).to eq('true')
    expect(evaluate([{ 'type' => 'label', 'operator' => 'not_has', 'label_ids' => [vip.id] }])).to eq('false')
  end

  it 'atributo da conversa e do contato, com comparação numérica' do
    expect(evaluate([{ 'type' => 'attribute', 'scope' => 'conversation', 'key' => 'servico', 'operator' => 'equals',
                       'value' => 'escova' }])).to eq('true')
    expect(evaluate([{ 'type' => 'attribute', 'scope' => 'contact', 'key' => 'pontos', 'operator' => 'greater', 'value' => '10' }])).to eq('true')
    expect(evaluate([{ 'type' => 'attribute', 'scope' => 'contact', 'key' => 'email', 'operator' => 'present' }])).to eq('false')
  end

  it 'origem do lead e "qualquer" entre regras' do
    expect(evaluate([{ 'type' => 'lead_source', 'value' => 'anuncio_facebook' }])).to eq('true')
    expect(evaluate([{ 'type' => 'lead_source', 'value' => 'organico' }, { 'type' => 'label', 'label_ids' => [vip.id] }],
                    match: 'any')).to eq('false')
  end

  it 'cliente recorrente pela etiqueta' do
    expect(evaluate([{ 'type' => 'recurring', 'value' => true }])).to eq('false')
    conversation.update_labels(['cliente-recorrente'])
    expect(evaluate([{ 'type' => 'recurring', 'value' => true }])).to eq('true')
  end

  it 'horário de funcionamento da caixa' do
    allow(conversation.inbox).to receive(:working_now?).and_return(false)
    expect(evaluate([{ 'type' => 'business_hours', 'value' => 'closed' }])).to eq('true')
  end

  it 'dia da semana e hora no fuso da conta' do
    wednesday_10h = ActiveSupport::TimeZone['America/Sao_Paulo'].local(2026, 10, 21, 10, 30)
    rule = { 'type' => 'schedule', 'weekdays' => [1, 2, 3, 4, 5], 'from' => '09:00', 'to' => '18:00' }

    expect(evaluate([rule], now: wednesday_10h)).to eq('true')
    expect(evaluate([rule], now: wednesday_10h.change(hour: 19))).to eq('false')
    expect(evaluate([rule], now: wednesday_10h + 3.days)).to eq('false')
  end
end

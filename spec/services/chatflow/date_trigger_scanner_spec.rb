require 'rails_helper'

RSpec.describe Chatflow::DateTriggerScanner do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:zone) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  # Quarta-feira, 10h30 em São Paulo: janela de envio aberta.
  let(:now) { zone.local(2026, 10, 21, 10, 30) }

  def date_flow(config)
    flow = Chatflow.create!(account: account, name: 'Data', inbox: inbox, status: :active, trigger_type: :date,
                            trigger_config: { 'date' => config })
    flow.update!(start_node: flow_node(flow, :send_message, 'text' => 'Feliz dia!'))
    flow
  end

  def scan(at = now)
    travel_to(at) { described_class.new.perform(now: at) }
  end

  before { allow(Redis::Alfred).to receive(:set).and_return(true) }

  it 'aniversário: aceita ISO e dd/mm/aaaa e começa uma vez por dia' do
    date_flow('kind' => 'birthday', 'attribute_key' => 'data_nascimento', 'hour' => 9)
    ana = create(:contact, account: account, custom_attributes: { 'data_nascimento' => '1990-10-21' })
    bia = create(:contact, account: account, custom_attributes: { 'data_nascimento' => '21/10/1985' })
    eva = create(:contact, account: account, custom_attributes: { 'data_nascimento' => '1990-05-02' })
    conversations = [ana, bia, eva].map { |c| create(:conversation, account: account, inbox: inbox, contact: c) }

    scan
    scan(now + 1.hour)

    expect(conversations.map { |c| bot_said(c).size }).to eq([1, 1, 0])
  end

  it 'fora da janela (domingo ou antes da hora) não começa' do
    date_flow('kind' => 'birthday', 'hour' => 9)
    contact = create(:contact, account: account, custom_attributes: { 'data_nascimento' => '1990-10-25' })
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact)

    scan(zone.local(2026, 10, 25, 10)) # domingo
    expect(bot_said(conversation)).to be_empty
  end

  it 'respeita a hora configurada' do
    date_flow('kind' => 'birthday', 'hour' => 15)
    contact = create(:contact, account: account, custom_attributes: { 'data_nascimento' => '2000-10-21' })
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact)

    scan
    expect(bot_said(conversation)).to be_empty
    scan(now.change(hour: 15))
    expect(bot_said(conversation).size).to eq(1)
  end

  it 'X dias depois do agendamento' do
    date_flow('kind' => 'after_appointment', 'days' => 1, 'hour' => 9)
    yesterday = create(:conversation, account: account, inbox: inbox, custom_attributes: { 'data_agendamento' => '2026-10-20T15:00:00-03:00' })
    today = create(:conversation, account: account, inbox: inbox, custom_attributes: { 'data_agendamento' => '2026-10-21T15:00:00-03:00' })

    scan
    expect(bot_said(yesterday).size).to eq(1)
    expect(bot_said(today)).to be_empty
  end

  it 'X dias depois de entrar num estágio (etiqueta)' do
    label = create(:label, account: account, title: 'agendado')
    date_flow('kind' => 'after_stage', 'days' => 2, 'label_id' => label.id, 'hour' => 9)
    staged = create(:conversation, account: account, inbox: inbox)
    travel_to(now - 2.days) { staged.update_labels(['agendado']) }
    recent = create(:conversation, account: account, inbox: inbox)
    recent.update_labels(['agendado'])

    scan
    expect(bot_said(staged).size).to eq(1)
    expect(bot_said(recent)).to be_empty
  end

  it 'X dias depois do atendimento encerrado' do
    date_flow('kind' => 'after_resolution', 'days' => 3, 'hour' => 9)
    conversation = create(:conversation, account: account, inbox: inbox)
    create(:reporting_event, account: account, conversation: conversation, name: 'conversation_resolved', created_at: now - 3.days)

    scan
    expect(bot_said(conversation).size).to eq(1)
  end

  it 'a trava do Redis deixa passar uma vez por hora' do
    allow(Redis::Alfred).to receive(:set).and_return(false)
    flow = date_flow('kind' => 'birthday', 'hour' => 9)

    scan
    expect(flow.executions).to be_empty
  end
end

require 'rails_helper'

RSpec.describe Conversations::ScheduleService do
  let(:account) { create(:account, custom_attributes: { 'vertical_template' => 'beauty_salon' }) }
  let(:conversation) { create(:conversation, account: account, status: :open) }
  let(:attributes) do
    { 'servico' => 'Corte', 'profissional' => 'Ana', 'data_agendamento' => '2026-10-25T14:00:00.000Z', 'ciclo_recompra_semanas' => '4' }
  end

  before do
    vertical = Vertical.create!(key: 'beauty_salon', name: 'Salão de beleza')
    [%w[novo-contato 1], %w[triagem 2], %w[em-atendimento 3], %w[agendado 4]].each do |title, position|
      vertical.vertical_statuses.create!(title: title, position: position, color: '#14B8A6')
    end
    vertical.vertical_statuses.create!(title: 'cancelado', position: 9, color: '#EF4444', closes_conversation: true)
    %w[novo-contato triagem agendado lead-anuncio].each { |title| create(:label, account: account, title: title) }
  end

  it 'stores the appointment on the conversation and tags it agendado' do
    conversation.update!(custom_attributes: { 'anuncio_id' => '1', 'origem_lead' => 'anuncio_facebook' })

    described_class.new(conversation: conversation, attributes: attributes).perform

    conversation.reload
    expect(conversation.custom_attributes).to include(attributes.merge('anuncio_id' => '1', 'origem_lead' => 'anuncio_facebook'))
    expect(conversation.label_list).to include('agendado')
  end

  it 'replaces the previous stage of the vertical but keeps the other labels' do
    conversation.update!(label_list: %w[triagem lead-anuncio])

    described_class.new(conversation: conversation, attributes: attributes).perform

    expect(conversation.reload.label_list).to contain_exactly('lead-anuncio', 'agendado')
  end

  it 'ignores blank fields so an empty form does not wipe what is already there' do
    conversation.update!(custom_attributes: { 'profissional' => 'Bia' })

    described_class.new(conversation: conversation, attributes: { 'servico' => 'Escova', 'profissional' => '' }).perform

    expect(conversation.reload.custom_attributes).to include('servico' => 'Escova', 'profissional' => 'Bia')
  end

  it 'only adds agendado when the account has no vertical' do
    account.update!(custom_attributes: {})
    conversation.update!(label_list: %w[triagem])

    described_class.new(conversation: conversation, attributes: attributes).perform

    expect(conversation.reload.label_list).to contain_exactly('triagem', 'agendado')
  end

  it 'moves the kanban card to the column named Agendado' do
    funnel = create(:funnel, account: account)
    triage = create(:funnel_stage, funnel: funnel, name: 'Triagem', position: 1)
    scheduled = create(:funnel_stage, funnel: funnel, name: 'Agendado', position: 2)
    task = create(:kanban_task, account: account, funnel: funnel, funnel_stage: triage)
    task.conversations << conversation

    described_class.new(conversation: conversation, attributes: attributes).perform

    expect(task.reload.funnel_stage).to eq(scheduled)
  end
end

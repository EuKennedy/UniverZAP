require 'rails_helper'

RSpec.describe Whatsapp::Flows::ApplyResponseService do
  let(:flow) { create(:whatsapp_flow, :published) }
  let(:account) { flow.account }
  let(:conversation) { create(:conversation, inbox: flow.inbox, account: account) }

  def reply(fields)
    create(:message, conversation: conversation, account: account, message_type: :incoming,
                     content: 'x', content_attributes: { flow_response: { flow_id: flow.id, fields: fields } })
  end

  before do
    account.custom_attribute_definitions.create!(attribute_key: 'servico', attribute_display_name: 'Serviço',
                                                 attribute_model: 'conversation_attribute', attribute_display_type: 'list')
    account.custom_attribute_definitions.create!(attribute_key: 'observacao', attribute_display_name: 'Obs',
                                                 attribute_model: 'contact_attribute', attribute_display_type: 'text')
  end

  it 'grava cada campo no alvo do mapeamento e aplica as etiquetas que a conta tem' do
    create(:label, account: account, title: 'agendado')
    message = reply([{ name: 'servico', label: 'Serviço', value: 'Corte', raw: 'corte' },
                     { name: 'observacao', label: 'Obs', value: 'sem amônia', raw: 'sem amônia' }])

    described_class.new(message).perform

    expect(conversation.reload.custom_attributes['servico']).to eq('Corte')
    expect(conversation.contact.reload.custom_attributes['observacao']).to eq('sem amônia')
    expect(conversation.label_list).to include('agendado')
  end

  it 'não inventa etiqueta que a conta não tem nem apaga atributos já gravados' do
    conversation.update!(custom_attributes: { 'origem' => 'instagram' })
    message = reply([{ name: 'servico', label: 'Serviço', value: 'Corte', raw: 'corte' }])

    described_class.new(message).perform

    expect(conversation.reload.custom_attributes).to eq('origem' => 'instagram', 'servico' => 'Corte')
    expect(conversation.label_list).to be_empty
  end

  it 'converte pelo tipo do atributo' do
    account.custom_attribute_definitions.create!(attribute_key: 'nota', attribute_display_name: 'Nota',
                                                 attribute_model: 'conversation_attribute', attribute_display_type: 'number')
    flow.update!(field_mappings: { 'fields' => { 'nota' => { 'model' => 'conversation', 'key' => 'nota' } } })
    message = reply([{ name: 'nota', label: 'Nota', value: '4', raw: '4' }])

    described_class.new(message).perform

    expect(conversation.reload.custom_attributes['nota']).to eq(4.0)
  end

  it 'ignora resposta sem Flow conhecido' do
    message = create(:message, conversation: conversation, account: account, message_type: :incoming,
                               content: 'x', content_attributes: { flow_response: { fields: [] } })

    expect { described_class.new(message).perform }.not_to raise_error
  end
end

require 'rails_helper'

# O envio de Flow pelo provider Cloud: interativo `type: flow` com o token
# assinado, o id da Meta e o modo (rascunho só em teste).
describe Whatsapp::Providers::WhatsappCloudService do
  subject(:service) { described_class.new(whatsapp_channel: whatsapp_channel) }

  let(:flow) { create(:whatsapp_flow, :published) }
  let(:whatsapp_channel) { flow.inbox.channel }
  let(:conversation) { create(:conversation, inbox: flow.inbox, account: flow.account) }
  let(:message) { Whatsapp::Flows::SendService.new(flow: flow, conversation: conversation, text: 'Vamos agendar?', cta: 'Agendar').perform }

  before do
    stub_request(:get, 'https://graph.facebook.com/v14.0/123456789/message_templates?access_token=test_key')
  end

  it 'manda o interativo de Flow com token assinado e a primeira tela' do
    stub = stub_request(:post, 'https://graph.facebook.com/v13.0/123456789/messages')
           .with { |request| flow_request?(JSON.parse(request.body)) }
           .to_return(status: 200, body: { messages: [{ id: 'wamid.1' }] }.to_json, headers: { 'Content-Type' => 'application/json' })

    expect(service.send_message('+5511999999999', message)).to eq('wamid.1')
    expect(stub).to have_been_requested
  end

  def flow_request?(body)
    params = body.dig('interactive', 'action', 'parameters')
    interactive_flow?(body) && flow_params?(params) &&
      Whatsapp::Flows::FlowToken.message_for(params['flow_token']) == message
  end

  def interactive_flow?(body)
    body['type'] == 'interactive' && body.dig('interactive', 'type') == 'flow' &&
      body.dig('interactive', 'body', 'text') == 'Vamos agendar?'
  end

  def flow_params?(params)
    params.slice('flow_id', 'flow_cta', 'mode', 'flow_message_version') ==
      { 'flow_id' => flow.meta_flow_id, 'flow_cta' => 'Agendar', 'mode' => 'published', 'flow_message_version' => '3' } &&
      params.dig('flow_action_payload', 'screen') == 'AGENDAMENTO'
  end
end

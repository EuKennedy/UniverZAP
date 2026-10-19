require 'rails_helper'

# A resposta de um Flow chega como `interactive.nfm_reply` no mesmo webhook
# de mensagens. Vira mensagem legível, guarda os dados e agenda o mapeamento.
describe Whatsapp::IncomingMessageWhatsappCloudService do
  let(:flow) { create(:whatsapp_flow, :published, name: 'Agendamento') }
  let(:whatsapp_channel) { flow.inbox.channel }
  # O contato que vai responder já existe com o wa_id do webhook, para a
  # resposta cair na MESMA conversa em que o formulário foi mandado.
  let(:contact) { create(:contact, account: flow.account, phone_number: '+5511999999999') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: flow.inbox, source_id: '5511999999999') }
  let(:conversation) { create(:conversation, inbox: flow.inbox, account: flow.account, contact: contact, contact_inbox: contact_inbox) }
  let(:original) { Whatsapp::Flows::SendService.new(flow: flow, conversation: conversation, text: 'Vamos?', cta: 'Agendar').perform }
  let(:token) { Whatsapp::Flows::FlowToken.generate(original.id) }
  let(:params) do
    {
      phone_number: whatsapp_channel.phone_number,
      object: 'whatsapp_business_account',
      entry: [{
        changes: [{
          value: {
            contacts: [{ profile: { name: 'Maria' }, wa_id: '5511999999999' }],
            messages: [{
              from: '5511999999999', id: 'wamid.reply', timestamp: '1664799904', type: 'interactive',
              context: { from: '5511888888888', id: 'wamid.flow' },
              interactive: {
                type: 'nfm_reply',
                nfm_reply: { name: 'flow', body: 'Sent', response_json: { flow_token: token, servico: 'corte', observacao: 'sem amônia' }.to_json }
              }
            }]
          }
        }]
      }]
    }.with_indifferent_access
  end

  after do
    Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) }
  end

  it 'cria a mensagem com o texto legível, os dados do Flow e agenda o mapeamento' do
    original.update!(source_id: 'wamid.flow')

    expect do
      described_class.new(inbox: whatsapp_channel.inbox, params: params).perform
    end.to have_enqueued_job(Whatsapp::Flows::ApplyResponseJob)

    message = whatsapp_channel.inbox.messages.incoming.find_by(source_id: 'wamid.reply')
    expect(message.content).to eq("Agendamento\nServiço: Corte\nObservações: sem amônia")
    expect(message.content_attributes['flow_response']['flow_id']).to eq(flow.id)
    # A resposta chega citando a mensagem do formulário.
    expect(message.content_attributes['in_reply_to']).to eq(original.id)
  end
end

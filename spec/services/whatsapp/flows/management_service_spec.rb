require 'rails_helper'

RSpec.describe Whatsapp::Flows::ManagementService do
  let(:flow) { create(:whatsapp_flow) }
  let(:channel) { flow.inbox.channel }
  let(:service) { described_class.new(channel) }
  let(:base) { 'https://graph.facebook.com/v22.0' }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }

  describe '#push' do
    it 'cria o Flow na Meta e guarda o id e os erros de validação' do
      stub_request(:post, "#{base}/#{channel.provider_config['business_account_id']}/flows")
        .with(body: hash_including('name' => flow.name, 'categories' => ['APPOINTMENT_BOOKING']))
        .to_return(status: 200, body: { id: 'f-1', validation_errors: [] }.to_json, headers: json_headers)

      result = service.push(flow)

      expect(result.success?).to be(true)
      expect(flow.reload.meta_flow_id).to eq('f-1')
    end

    # A Meta recebe o JSON como arquivo, não como campo do corpo.
    it 'reenvia o JSON como asset quando o Flow já existe na Meta' do
      flow.update!(meta_flow_id: 'f-1')
      stub_request(:post, "#{base}/f-1/assets")
        .to_return(status: 200, body: { success: true, validation_errors: [{ 'error' => 'INVALID_PROPERTY' }] }.to_json, headers: json_headers)

      result = service.push(flow)

      expect(result.success?).to be(true)
      expect(flow.reload.validation_errors.first['error']).to eq('INVALID_PROPERTY')
    end

    it 'repassa o motivo que a Meta deu' do
      stub_request(:post, "#{base}/#{channel.provider_config['business_account_id']}/flows")
        .to_return(status: 400, body: { error: { message: 'Invalid Flow JSON' } }.to_json, headers: json_headers)

      expect(service.push(flow).error).to eq('Invalid Flow JSON')
    end

    it 'não deixa uma falha de rede escapar' do
      stub_request(:post, "#{base}/#{channel.provider_config['business_account_id']}/flows").to_timeout

      expect(service.push(flow).error).to eq('unreachable')
    end
  end

  describe '#publish' do
    it 'recusa publicar o que ainda não foi para a Meta' do
      expect(service.publish(flow).error).to eq('not_on_meta')
    end

    it 'marca como publicado quando a Meta aceita' do
      flow.update!(meta_flow_id: 'f-1')
      stub_request(:post, "#{base}/f-1/publish").to_return(status: 200, body: { success: true }.to_json, headers: json_headers)

      service.publish(flow)

      expect(flow.reload).to be_published
      expect(flow.published_at).to be_present
    end
  end

  describe '#sync' do
    it 'traz estado e link de prévia da Meta' do
      flow.update!(meta_flow_id: 'f-1')
      stub_request(:get, "#{base}/f-1?fields=status,validation_errors,preview.invalidate(false)")
        .to_return(status: 200, headers: json_headers,
                   body: { status: 'PUBLISHED', preview: { preview_url: 'https://business.facebook.com/wa/manage/flows/f-1/preview' } }.to_json)

      service.sync(flow)

      expect(flow.reload.status).to eq('published')
      expect(flow.preview_url).to include('preview')
    end
  end

  describe '#destroy' do
    it 'apaga na Meta só quando é rascunho, e sempre apaga aqui' do
      flow.update!(meta_flow_id: 'f-1')
      stub_request(:delete, "#{base}/f-1").to_return(status: 200, body: { success: true }.to_json, headers: json_headers)

      expect { service.destroy(flow) }.to change(WhatsappFlow, :count).by(-1)
    end

    it 'não chama a Meta para um depreciado' do
      flow.update!(meta_flow_id: 'f-1', status: 'deprecated')

      expect { service.destroy(flow) }.to change(WhatsappFlow, :count).by(-1)
      expect(WebMock).not_to have_requested(:delete, "#{base}/f-1")
    end
  end
end

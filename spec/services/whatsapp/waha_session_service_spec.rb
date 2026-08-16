require 'rails_helper'

RSpec.describe Whatsapp::WahaSessionService do
  subject(:service) { described_class.new(session_name: 'default', base_url: 'https://waha.test', api_key: 'k') }

  describe '#send_text' do
    let(:endpoint) { 'https://waha.test/api/sendText' }

    before { stub_request(:post, endpoint).to_return(status: 200, body: { id: 'x' }.to_json) }

    # The quoted reply. WAHA takes the id of the message being answered; the
    # Cloud provider has always sent its equivalent, so this is the field that
    # made an agent's quote survive on one provider and vanish on the other.
    it 'forwards the id of the message being quoted' do
      service.send_text(chat_id: '55119@c.us', text: 'Oi', reply_to: 'false_55119@c.us_ABC')

      expect(a_request(:post, endpoint).with { |req| JSON.parse(req.body)['reply_to'] == 'false_55119@c.us_ABC' })
        .to have_been_made
    end

    # Sent as an absent key rather than an explicit null: WAHA rejects null here.
    it 'omits the field entirely on an ordinary reply' do
      service.send_text(chat_id: '55119@c.us', text: 'Oi')

      expect(a_request(:post, endpoint).with { |req| !JSON.parse(req.body).key?('reply_to') }).to have_been_made
    end
  end

  # https://waha.devlike.pro/docs/how-to/profile/
  describe 'profile' do
    let(:json) { { 'Content-Type' => 'application/json' } }

    it 'reads the profile of the connected number' do
      stub_request(:get, 'https://waha.test/api/default/profile')
        .to_return(status: 200, headers: json, body: { id: '5511@c.us', name: 'Loja da Ana' }.to_json)

      expect(service.profile['name']).to eq('Loja da Ana')
    end

    it 'sends the new name' do
      stub_request(:put, 'https://waha.test/api/default/profile/name').to_return(status: 200, headers: json, body: '{}')

      service.update_profile_name('Loja da Ana')

      expect(a_request(:put, 'https://waha.test/api/default/profile/name')
        .with(body: { name: 'Loja da Ana' }.to_json)).to have_been_made
    end

    # O recado do WhatsApp chega na WAHA como `status`, que é o mesmo nome que
    # ela usa para o estado da sessão. O teste fixa o campo certo.
    it 'sends the about text on the field WAHA calls status' do
      stub_request(:put, 'https://waha.test/api/default/profile/status').to_return(status: 200, headers: json, body: '{}')

      service.update_profile_about('Aberto das 9h às 18h')

      expect(a_request(:put, 'https://waha.test/api/default/profile/status')
        .with(body: { status: 'Aberto das 9h às 18h' }.to_json)).to have_been_made
    end

    it 'sends the picture as a url for WAHA to download' do
      stub_request(:put, 'https://waha.test/api/default/profile/picture').to_return(status: 200, headers: json, body: '{}')

      service.update_profile_picture(url: 'https://cdn.test/logo.jpg')

      expect(a_request(:put, 'https://waha.test/api/default/profile/picture')
        .with(body: { file: { url: 'https://cdn.test/logo.jpg' } }.to_json)).to have_been_made
    end

    it 'removes the picture' do
      stub_request(:delete, 'https://waha.test/api/default/profile/picture').to_return(status: 200, headers: json, body: '{}')

      service.delete_profile_picture

      expect(a_request(:delete, 'https://waha.test/api/default/profile/picture')).to have_been_made
    end

    it 'raises WahaError when WAHA refuses the change' do
      stub_request(:put, 'https://waha.test/api/default/profile/name')
        .to_return(status: 422, body: { message: 'name too long' }.to_json)

      expect { service.update_profile_name('x' * 500) }.to raise_error(described_class::WahaError, /422/)
    end
  end

  # https://waha.devlike.pro/docs/how-to/status/
  describe 'status' do
    let(:json) { { 'Content-Type' => 'application/json' } }

    it 'publishes a text status with the chosen background' do
      stub_request(:post, 'https://waha.test/api/default/status/text').to_return(status: 200, headers: json, body: '{}')

      service.send_status_text(text: 'Promoção hoje', background_color: '#38B42F')

      expect(a_request(:post, 'https://waha.test/api/default/status/text')
        .with(body: { text: 'Promoção hoje', backgroundColor: '#38B42F' }.to_json)).to have_been_made
    end

    # Sem `contacts` a WAHA publica para todos os contatos, que é o que a tela
    # promete, e é também o único formato que o engine WEBJS aceita.
    it 'never restricts the audience to a contact list' do
      stub_request(:post, 'https://waha.test/api/default/status/text').to_return(status: 200, headers: json, body: '{}')

      service.send_status_text(text: 'Promoção hoje')

      expect(a_request(:post, 'https://waha.test/api/default/status/text')
        .with { |req| (JSON.parse(req.body).keys & %w[contacts backgroundColor]).empty? }).to have_been_made
    end

    it 'publishes an image status with caption and mimetype' do
      stub_request(:post, 'https://waha.test/api/default/status/image').to_return(status: 200, headers: json, body: '{}')

      service.send_status_image(url: 'https://cdn.test/a.png', caption: 'Chegou', mimetype: 'image/png')

      expect(a_request(:post, 'https://waha.test/api/default/status/image')
        .with(body: { file: { mimetype: 'image/png', url: 'https://cdn.test/a.png' }, caption: 'Chegou' }.to_json))
        .to have_been_made
    end

    # O WhatsApp só aceita status em mp4/libx264, então pedimos a conversão à
    # WAHA em vez de confiar no que o operador subiu do celular.
    it 'asks WAHA to convert the video and sends no caption' do
      stub_request(:post, 'https://waha.test/api/default/status/video').to_return(status: 200, headers: json, body: '{}')

      service.send_status_video(url: 'https://cdn.test/v.mov', mimetype: 'video/quicktime')

      expect(a_request(:post, 'https://waha.test/api/default/status/video')
        .with { |req| JSON.parse(req.body).values_at('convert', 'caption') == [true, nil] }).to have_been_made
    end

    it 'raises WahaError when the session is not connected' do
      stub_request(:post, 'https://waha.test/api/default/status/text')
        .to_return(status: 422, body: { message: 'session status is not WORKING' }.to_json)

      expect { service.send_status_text(text: 'Oi') }.to raise_error(described_class::WahaError, /422/)
    end
  end
end

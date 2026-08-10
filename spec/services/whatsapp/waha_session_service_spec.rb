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
end

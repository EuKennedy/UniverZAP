require 'rails_helper'

RSpec.describe Whatsapp::StatusPosts::Publisher do
  let(:account) { create(:account) }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:loja) { waha_inbox('u1-loja', 'Loja') }
  let(:filial) { waha_inbox('u1-filial', 'Filial') }

  def waha_inbox(session, name)
    create(:channel_api, account: account, additional_attributes: { 'source' => 'waha', 'session_name' => session })
      .reload.inbox.tap { |inbox| inbox.update!(name: name) }
  end

  around do |example|
    with_modified_env(WAHA_BASE_URL: 'https://waha.test', WAHA_API_KEY: 'k') { example.run }
  end

  it 'posts a text status to every connection with colour and font' do
    stub_request(:post, %r{https://waha\.test/api/u1-.+/status/text})
      .to_return(status: 200, headers: json, body: { id: { _serialized: 'true_status@broadcast_ABC' } }.to_json)
    post = create(:whatsapp_status_post, account: account, status: :publishing, font: 2, inbox_ids: [loja.id, filial.id])

    described_class.new(post).perform

    expect(post.reload).to be_status_published
    expect(post.deliveries.pluck(:inbox_name, :status)).to contain_exactly(%w[Loja sent], %w[Filial sent])
    expect(post.deliveries.first.waha_message_id).to eq('true_status@broadcast_ABC')
    expect(a_request(:post, 'https://waha.test/api/u1-filial/status/text')
      .with(body: { text: 'Agenda aberta para sábado', backgroundColor: '#0A5F55', font: 2 }.to_json)).to have_been_made
  end

  it 'records the WAHA error per connection and keeps the ones that worked' do
    stub_request(:post, 'https://waha.test/api/u1-loja/status/text').to_return(status: 200, headers: json, body: '{}')
    stub_request(:post, 'https://waha.test/api/u1-filial/status/text')
      .to_return(status: 422, headers: json, body: { message: 'session status is not WORKING' }.to_json)
    post = create(:whatsapp_status_post, account: account, status: :publishing, inbox_ids: [loja.id, filial.id])

    described_class.new(post).perform

    expect(post.reload).to be_status_partially_published
    failed = post.deliveries.status_failed.sole
    expect([failed.inbox_name, failed.error_message]).to eq(['Filial', 'session status is not WORKING'])
  end

  # Timeout não diz se o status saiu: falha, mas sem repetir sozinho.
  it 'marks a timeout as failed without retrying' do
    stub_request(:post, 'https://waha.test/api/u1-loja/status/text').to_timeout
    post = create(:whatsapp_status_post, account: account, status: :publishing, inbox_ids: [loja.id])

    described_class.new(post).perform

    expect(post.reload).to be_status_failed
    expect(post.deliveries.sole.error_message).to eq(I18n.t('inbox.whatsapp.waha.status_timeout'))
    expect(a_request(:post, 'https://waha.test/api/u1-loja/status/text')).to have_been_made.once
  end

  it 'only resends the deliveries that are pending, never the ones already sent' do
    stub_request(:post, %r{https://waha\.test/api/u1-.+/status/text}).to_return(status: 200, headers: json, body: '{}')
    post = create(:whatsapp_status_post, account: account, status: :publishing, inbox_ids: [loja.id, filial.id])
    post.deliveries.create!(inbox: loja, inbox_name: 'Loja', status: :sent)
    post.deliveries.create!(inbox: filial, inbox_name: 'Filial', status: :pending)

    described_class.new(post).perform

    expect(a_request(:post, 'https://waha.test/api/u1-loja/status/text')).not_to have_been_made
    expect(a_request(:post, 'https://waha.test/api/u1-filial/status/text')).to have_been_made.once
    expect(post.reload).to be_status_published
  end

  it 'sends image and video media as a downloadable url with the caption' do
    stub_request(:post, 'https://waha.test/api/u1-loja/status/video').to_return(status: 200, headers: json, body: '{}')
    post = build(:whatsapp_status_post, account: account, kind: 'video', body: 'Bastidores', status: :publishing, inbox_ids: [loja.id])
    post.media.attach(io: Rails.root.join('spec/assets/sample.mp4').open, filename: 'v.mp4', content_type: 'video/mp4')
    post.save!

    described_class.new(post).perform

    expect(a_request(:post, 'https://waha.test/api/u1-loja/status/video').with do |req|
      body = JSON.parse(req.body)
      body['caption'] == 'Bastidores' && body['convert'] == true && body.dig('file', 'url').include?('/rails/active_storage/')
    end).to have_been_made
  end

  it 'fills the variables with the name of each connection' do
    stub_request(:post, %r{https://waha\.test/api/u1-.+/status/text}).to_return(status: 200, headers: json, body: '{}')
    post = create(:whatsapp_status_post, account: account, status: :publishing, body: 'Hoje na {{conexao}}!',
                                         inbox_ids: [loja.id, filial.id])

    described_class.new(post).perform

    expect(a_request(:post, 'https://waha.test/api/u1-loja/status/text').with { |r| JSON.parse(r.body)['text'] == 'Hoje na Loja!' })
      .to have_been_made
    expect(a_request(:post, 'https://waha.test/api/u1-filial/status/text').with { |r| JSON.parse(r.body)['text'] == 'Hoje na Filial!' })
      .to have_been_made
  end
end

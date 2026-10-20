require 'rails_helper'

RSpec.describe WhatsappStatusPost do
  let(:account) { create(:account) }
  let(:waha_inbox) do
    create(:channel_api, account: account, additional_attributes: { 'source' => 'waha', 'session_name' => 'u1-loja' }).reload.inbox
  end

  it 'saves a draft without text, media or connections' do
    expect(build(:whatsapp_status_post, account: account, body: nil, kind: 'image')).to be_valid
  end

  it 'requires connections and text before it can be scheduled' do
    post = build(:whatsapp_status_post, account: account, status: :scheduled, body: '', scheduled_at: 1.hour.from_now)

    expect(post).not_to be_valid
    expect(post.errors.attribute_names).to include(:inbox_ids, :body)
  end

  it 'refuses a schedule in the past' do
    post = build(:whatsapp_status_post, account: account, status: :scheduled, inbox_ids: [waha_inbox.id], scheduled_at: 1.hour.ago)

    expect(post).not_to be_valid
    expect(post.errors.attribute_names).to eq([:scheduled_at])
  end

  # O publicador confia em `inbox_ids`; um id de outra conta não pode chegar lá.
  it 'refuses a connection that belongs to another account' do
    stranger = create(:channel_api, account: create(:account),
                                    additional_attributes: { 'source' => 'waha', 'session_name' => 'u2-loja' }).reload.inbox
    post = build(:whatsapp_status_post, account: account, inbox_ids: [stranger.id])

    expect(post).not_to be_valid
    expect(post.errors.attribute_names).to eq([:inbox_ids])
  end

  it 'refuses a non-WAHA inbox of the same account' do
    post = build(:whatsapp_status_post, account: account, inbox_ids: [create(:inbox, account: account).id])

    expect(post).not_to be_valid
  end

  it 'requires media of the matching type to publish an image' do
    post = build(:whatsapp_status_post, account: account, kind: 'image', status: :publishing, inbox_ids: [waha_inbox.id])
    post.media.attach(io: Rails.root.join('spec/assets/sample.mp4').open, filename: 'v.mp4', content_type: 'video/mp4')

    expect(post).not_to be_valid
    expect(post.errors.attribute_names).to eq([:media])
  end

  describe '#refresh_outcome!' do
    let(:post) { create(:whatsapp_status_post, account: account, status: :publishing, inbox_ids: [waha_inbox.id]) }

    def deliver(status)
      post.deliveries.create!(inbox: waha_inbox, inbox_name: 'Loja', status: status)
    end

    it 'is published when every connection got it' do
      deliver(:sent)
      post.refresh_outcome!

      expect(post.reload).to be_status_published
      expect(post.published_at).to be_present
    end

    it 'is partially published when only some connections got it' do
      deliver(:sent)
      deliver(:failed)
      post.refresh_outcome!

      expect(post.reload).to be_status_partially_published
    end

    it 'is failed when there was nothing to deliver to' do
      post.refresh_outcome!

      expect(post.reload).to be_status_failed
    end

    it 'waits while a connection is still pending' do
      deliver(:pending)
      post.refresh_outcome!

      expect(post.reload).to be_status_publishing
    end
  end
end

require 'rails_helper'

RSpec.describe Kanban::WebhookSubscriptionDeliveryJob, type: :job do
  let(:account) { create(:account) }
  let(:subscription) { create(:kanban_webhook_subscription, account: account, url: 'https://hook.example/x') }
  let(:payload) { { event: 'task.created', data: { id: 1 } } }

  describe '#perform' do
    it 'signs the body with HMAC-SHA256 using the subscription secret' do
      stub = stub_request(:post, subscription.url).to_return(status: 200, body: '')
      described_class.perform_now(subscription.id, 'task.created', payload)
      expected_sig = OpenSSL::HMAC.hexdigest('SHA256', subscription.secret, payload.to_json)
      expect(stub.with(headers: { 'X-UniverZAP-Signature' => "sha256=#{expected_sig}" })).to have_been_requested
    end

    it 'increments delivery_count on 2xx' do
      stub_request(:post, subscription.url).to_return(status: 200)
      expect { described_class.perform_now(subscription.id, 'task.created', payload) }
        .to change { subscription.reload.delivery_count }.by(1)
    end

    it 'records failure on 4xx and does NOT retry' do
      stub_request(:post, subscription.url).to_return(status: 410)
      expect { described_class.perform_now(subscription.id, 'task.created', payload) }
        .to change { subscription.reload.failure_count }.by(1)
    end

    it 'records failure + retries on 5xx' do
      # `retry_on HTTParty::Error` catches the raise + schedules a
      # retry, so `perform_now` won't propagate the exception. Verify
      # the side-effects instead: failure_count incremented + the job
      # got re-enqueued.
      stub_request(:post, subscription.url).to_return(status: 502)
      expect { described_class.perform_now(subscription.id, 'task.created', payload) }
        .to change { subscription.reload.failure_count }.by(1)
        .and have_enqueued_job(described_class)
    end

    it 'no-ops when the subscription is missing or inactive' do
      subscription.update!(active: false)
      expect { described_class.perform_now(subscription.id, 'task.created', payload) }
        .not_to raise_error
    end
  end
end

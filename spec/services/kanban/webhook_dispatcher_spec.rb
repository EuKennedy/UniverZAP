require 'rails_helper'

RSpec.describe Kanban::WebhookDispatcher do
  let(:account)  { create(:account) }
  let(:funnel)   { create(:funnel, account: account) }
  let(:stage)    { create(:funnel_stage, funnel: funnel) }
  let(:task)     { create(:kanban_task, account: account, funnel: funnel, funnel_stage: stage) }

  describe '.dispatch' do
    it 'enqueues a delivery job per matching subscription' do
      s1 = create(:kanban_webhook_subscription, account: account, events: [])
      s2 = create(:kanban_webhook_subscription, account: account, events: ['task.created'])
      _s3 = create(:kanban_webhook_subscription, account: account, events: ['task.deleted'])

      expect do
        described_class.dispatch('task.created', task)
      end.to have_enqueued_job(Kanban::WebhookSubscriptionDeliveryJob).exactly(2).times

      expect(Kanban::WebhookSubscriptionDeliveryJob).to have_been_enqueued.with(s1.id, 'task.created', anything)
      expect(Kanban::WebhookSubscriptionDeliveryJob).to have_been_enqueued.with(s2.id, 'task.created', anything)
    end

    it 'never crosses tenant boundary' do
      foreign = create(:kanban_webhook_subscription, events: [])
      expect do
        described_class.dispatch('task.created', task)
      end.not_to have_enqueued_job(Kanban::WebhookSubscriptionDeliveryJob).with(foreign.id, anything, anything)
    end

    it 'ignores unknown events' do
      create(:kanban_webhook_subscription, account: account, events: [])
      expect do
        described_class.dispatch('mystery.event', task)
      end.not_to have_enqueued_job(Kanban::WebhookSubscriptionDeliveryJob)
    end
  end
end

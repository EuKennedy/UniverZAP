require 'rails_helper'

RSpec.describe Ai::AutopilotReplyJob, type: :job do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, conversation: conversation, account: account, inbox: conversation.inbox) }

  before do
    # Bypass the real Claude/belezaki round-trip — we only exercise the job's
    # locking / dedup / guard logic here.
    allow_any_instance_of(Ai::AutopilotReplyService) # rubocop:disable RSpec/AnyInstance
      .to receive(:perform).and_return({ content: 'Olá!' })
  end

  def outgoing_count
    conversation.reload.messages.where(message_type: :outgoing).count
  end

  it 'posts one reply and stamps the trigger message id on the conversation' do
    expect { described_class.perform_now(message.id, assistant.id) }.to change { outgoing_count }.by(1)
    expect(conversation.reload.additional_attributes['autopilot_last_replied_message_id']).to eq(message.id)
  end

  it 'does not post a second reply when the same job is retried (dedup by message_id)' do
    described_class.perform_now(message.id, assistant.id)

    expect { described_class.perform_now(message.id, assistant.id) }.not_to(change { outgoing_count })
  end

  it 'aborts without replying when the assistant belongs to another account' do
    other_assistant = create(:ai_assistant, account: create(:account))

    expect(Ai::AutopilotReplyService).not_to receive(:new)
    expect { described_class.perform_now(message.id, other_assistant.id) }.not_to(change { outgoing_count })
  end
end

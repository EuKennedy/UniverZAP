require 'rails_helper'

RSpec.describe Ai::PruneInvocationLogsJob, type: :job do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }

  def invocation(created_at:)
    Ai::Invocation.create!(
      ai_assistant: assistant, account: account, phase: 'autopilot', model: 'claude-sonnet-4-5',
      status: 'success', cost_brl: 0.5, input_tokens: 100,
      system_prompt: 'a very long prompt snapshot', created_at: created_at
    )
  end

  # The whole point: drop the write-only snapshot on old rows, keep the billing
  # numbers the ROI panel divides revenue by.
  it 'clears the system prompt on rows past the window but keeps their metrics' do
    old = invocation(created_at: 40.days.ago)

    described_class.perform_now

    old.reload
    expect(old.system_prompt).to be_nil
    expect(old.cost_brl).to eq(0.5)
  end

  it 'leaves recent rows untouched' do
    recent = invocation(created_at: 2.days.ago)

    described_class.perform_now

    expect(recent.reload.system_prompt).to eq('a very long prompt snapshot')
  end
end

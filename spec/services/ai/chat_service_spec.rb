require 'rails_helper'

RSpec.describe Ai::ChatService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:assistant) { create(:ai_assistant, account: account, tone: 'sales') }
  let(:claude) { instance_double(Ai::ClaudeService) }
  let(:thread) do
    Ai::ChatThread.create!(account: account, user: user, ai_assistant: assistant, title: 'Test')
  end

  before { allow(Ai::ClaudeService).to receive(:new).and_return(claude) }

  it 'locks the copilot role and drops the customer sales tone' do
    captured = nil
    allow(claude).to receive(:chat) do |**kwargs|
      captured = kwargs[:system]
      { content: 'No que posso ajudar?', model: 'claude' }
    end

    described_class.new(thread: thread, user_message: 'olá consegue me ajudar?').perform

    expect(captured).to include('COPILOTO INTERNO')
    expect(captured).to include('NUNCA com o cliente')
    expect(captured).not_to include('foco em conversão')
  end

  it 'persists the user and assistant messages' do
    allow(claude).to receive(:chat).and_return({ content: 'ok', model: 'claude' })

    expect { described_class.new(thread: thread, user_message: 'oi').perform }
      .to change { thread.chat_messages.count }.by(2)
  end
end

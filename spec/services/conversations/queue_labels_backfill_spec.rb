require 'rails_helper'

RSpec.describe Conversations::QueueLabelsBackfill do
  let(:account) { create(:account) }

  def tagged(labels, **attrs)
    create(:conversation, account: account, **attrs).tap do |conversation|
      conversation.update_columns(status: attrs.fetch(:status, :open)) # rubocop:disable Rails/SkipsModelValidations
      conversation.set_tag_list_on(:labels, labels)
      conversation.save_tags
    end
  end

  before do
    %w[novo-contato em-atendimento agendado vip].each { |title| create(:label, account: account, title: title) }
    create(:label, account: account, title: 'atendimento-encerrado', closes_conversation: true)
  end

  it 'only counts when not applying' do
    conversation = tagged(%w[novo-contato vip], first_reply_created_at: 1.hour.ago)

    expect(described_class.new(account).perform).to eq('open' => 1)
    expect(conversation.reload.label_list).to contain_exactly('novo-contato', 'vip')
  end

  it 'moves answered conversations to em-atendimento and clears the resolved ones' do
    answered = tagged(%w[novo-contato vip], first_reply_created_at: 1.hour.ago)
    untouched = tagged(%w[novo-contato])
    resolved = tagged(%w[novo-contato vip], status: :resolved)
    scheduled = tagged(%w[agendado atendimento-encerrado], status: :resolved)

    described_class.new(account).perform(apply: true)

    expect(Conversation.find(answered.id).label_list).to contain_exactly('em-atendimento', 'vip')
    expect(Conversation.find(untouched.id).label_list).to contain_exactly('novo-contato')
    expect(Conversation.find(resolved.id).label_list).to contain_exactly('vip')
    expect(Conversation.find(scheduled.id).label_list).to contain_exactly('agendado')
    expect(Conversation.find(answered.id).cached_label_list).to include('em-atendimento')
  end

  it 'writes no activity' do
    conversation = tagged(%w[novo-contato], first_reply_created_at: 1.hour.ago)

    expect { described_class.new(account).perform(apply: true) }.not_to(change { conversation.messages.count })
  end

  it 'leaves accounts without the stage flow alone' do
    account.labels.find_by(title: 'em-atendimento').destroy!

    expect(described_class.new(account).perform).to eq(skipped: true)
  end
end

require 'rails_helper'
require 'rake'

RSpec.describe 'encerradas:backfill', type: :task do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  before do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task['encerradas:backfill'].reenable
    create(:label, account: account, title: 'atendimento-encerrado', closes_conversation: true)
    create(:label, account: account, title: 'agendado')
  end

  # Labels written straight to the tagging table, as before a closing label
  # resolved the conversation: the conversation stays open with the label.
  def closed_by_label_at(time, contact_wrote_at:)
    conversation = create(:conversation, account: account, inbox: inbox)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, created_at: 3.days.ago)
    if contact_wrote_at
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, created_at: contact_wrote_at)
    end
    travel_to(time) { conversation.update_columns(cached_label_list: 'agendado, atendimento-encerrado') } # rubocop:disable Rails/SkipsModelValidations
    %w[agendado atendimento-encerrado].each do |title|
      ActsAsTaggableOn::Tagging.create!(taggable: conversation, context: 'labels', created_at: time,
                                        tag: ActsAsTaggableOn::Tag.find_or_create_by!(name: title))
    end
    conversation
  end

  it 'resolves what was closed last and keeps open, without the label, what the contact reopened', :aggregate_failures do
    closed = closed_by_label_at(2.days.ago, contact_wrote_at: nil)
    reopened = closed_by_label_at(2.days.ago, contact_wrote_at: 1.day.ago)
    untouched = create(:conversation, account: account, inbox: inbox)

    expect(Rails.configuration.dispatcher).not_to receive(:dispatch)
    expect { Rake::Task['encerradas:backfill'].invoke(account.id.to_s) }
      .to output(/1 conversations resolved; 1 reopened/).to_stdout

    expect(closed.reload.status).to eq('resolved')
    expect(closed.waiting_since).to be_nil
    expect(reopened.reload.status).to eq('open')
    expect(reopened.label_list).to eq(%w[agendado])
    expect(reopened.cached_label_list_array).to eq(%w[agendado])
    expect(untouched.reload.status).to eq('open')
  end
end

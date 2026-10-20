require 'rails_helper'
require 'rake'

RSpec.describe 'recorrencia:backfill', type: :task do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  before do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task['recorrencia:backfill'].reenable
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
  end

  def conversation(contact, **attrs)
    create(:conversation, account: account, inbox: inbox, contact: contact, **attrs)
  end

  # One conversation per contact, as the WAHA bridge keeps it: the contact
  # writes, the conversation gets resolved (ReportingEventListener records it),
  # and the contact's next message reopens the same conversation.
  def returned_in_place(contact)
    single = conversation(contact, created_at: 3.days.ago)
    create(:message, account: account, inbox: inbox, conversation: single, message_type: :incoming, content: 'oi', created_at: 3.days.ago)
    create(:reporting_event, name: 'conversation_resolved', account: account, inbox: inbox, conversation: single, user: nil,
                             event_start_time: 3.days.ago, event_end_time: 2.days.ago)
    create(:message, account: account, inbox: inbox, conversation: single, message_type: :incoming, content: 'voltei', created_at: 1.day.ago)
    single
  end

  it 'labels open conversations of returning customers and stamps contacts without firing events', :aggregate_failures do
    returning = create(:contact, account: account)
    conversation(returning, status: :resolved, created_at: 2.days.ago)
    open_again = conversation(returning)

    first_timer = create(:contact, account: account)
    only_one = conversation(first_timer)

    done_twice = create(:contact, account: account)
    conversation(done_twice, status: :resolved, created_at: 2.days.ago)
    last_closed = conversation(done_twice, status: :resolved)

    from_ad = create(:contact, account: account)
    conversation(from_ad, status: :resolved, created_at: 2.days.ago, custom_attributes: { 'anuncio_id' => '42' })
    ad_again = conversation(from_ad)

    reopened = create(:contact, account: account)
    same_again = returned_in_place(reopened)

    reopened_and_closed = create(:contact, account: account)
    closed_twice = returned_in_place(reopened_and_closed)
    closed_twice.resolved!

    expect { Rake::Task['recorrencia:backfill'].invoke(account.id) }
      .to output(/3 open conversations labelled cliente-recorrente; 5 contacts stamped recorrente; origem_lead filled on 6 contacts/).to_stdout

    expect(open_again.reload.label_list).to eq(['cliente-recorrente'])
    expect(ad_again.reload.label_list).to eq(['cliente-recorrente'])
    expect(same_again.reload.label_list).to eq(['cliente-recorrente'])
    expect(only_one.reload.label_list).to eq([])
    expect(last_closed.reload.label_list).to eq([])
    expect(closed_twice.reload.label_list).to eq([])
    expect(reopened.reload.custom_attributes).to include('recorrente' => true, 'origem_lead' => 'organico')
    expect(reopened_and_closed.reload.custom_attributes).to include('recorrente' => true, 'origem_lead' => 'organico')
    expect(returning.reload.custom_attributes).to include('recorrente' => true, 'origem_lead' => 'organico')
    expect(done_twice.reload.custom_attributes).to include('recorrente' => true, 'origem_lead' => 'organico')
    expect(from_ad.reload.custom_attributes).to include('recorrente' => true, 'origem_lead' => 'anuncio_facebook')
    expect(first_timer.reload.custom_attributes).to eq('origem_lead' => 'organico')
    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(Events::Types::CONVERSATION_RECURRING_CUSTOMER, anything, anything)
  end

  it 'is idempotent' do
    returning = create(:contact, account: account)
    conversation(returning, status: :resolved, created_at: 2.days.ago)
    conversation(returning)
    Rake::Task['recorrencia:backfill'].invoke(account.id)
    Rake::Task['recorrencia:backfill'].reenable

    expect { Rake::Task['recorrencia:backfill'].invoke(account.id) }
      .to output(/0 open conversations labelled cliente-recorrente; 0 contacts stamped recorrente; origem_lead filled on 0 contacts/).to_stdout
  end
end

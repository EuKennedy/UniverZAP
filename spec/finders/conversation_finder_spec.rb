require 'rails_helper'

describe ConversationFinder do
  subject(:conversation_finder) { described_class.new(user_1, params) }

  let!(:account) { create(:account) }
  let!(:user_1) { create(:user, account: account) }
  let!(:user_2) { create(:user, account: account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let!(:contact_inbox) { create(:contact_inbox, inbox: inbox, source_id: 'testing_source_id') }
  let!(:restricted_inbox) { create(:inbox, account: account) }

  before do
    create(:inbox_member, user: user_1, inbox: inbox)
    create(:inbox_member, user: user_2, inbox: inbox)
    create(:conversation, account: account, inbox: inbox, assignee: user_1)
    create(:conversation, account: account, inbox: inbox, assignee: user_1)
    create(:conversation, account: account, inbox: inbox, assignee: user_1, status: 'resolved')
    create(:conversation, account: account, inbox: inbox, assignee: user_2, contact_inbox: contact_inbox)
    # unassigned conversation
    create(:conversation, account: account, inbox: inbox)
    Current.account = account
  end

  describe '#perform' do
    context 'with status' do
      let(:params) { { status: 'open', assignee_type: 'me' } }

      it 'filter conversations by status' do
        result = conversation_finder.perform
        expect(result[:conversations].length).to be 2
      end
    end

    context 'with inbox' do
      let!(:restricted_conversation) { create(:conversation, account: account, inbox_id: restricted_inbox.id) }

      it 'returns conversation from any inbox if its admin' do
        params = { inbox_id: restricted_inbox.id }
        result = described_class.new(admin, params).perform

        expect(result[:conversations].map(&:id)).to include(restricted_conversation.id)
      end

      it 'returns conversation from inbox if agent is its member' do
        params = { inbox_id: restricted_inbox.id }
        create(:inbox_member, user: user_1, inbox: restricted_inbox)
        result = described_class.new(user_1, params).perform

        expect(result[:conversations].map(&:id)).to include(restricted_conversation.id)
      end

      it 'does not return conversations from inboxes where agent is not a member' do
        params = { inbox_id: restricted_inbox.id }
        result = described_class.new(user_1, params).perform

        expect(result[:conversations].map(&:id)).not_to include(restricted_conversation.id)
      end

      it 'returns only the conversations from the inbox if inbox_id filter is passed' do
        conversation = create(:conversation, account: account, inbox_id: inbox.id)
        params = { inbox_id: restricted_inbox.id }
        result = described_class.new(admin, params).perform

        conversation_ids = result[:conversations].map(&:id)
        expect(conversation_ids).not_to include(conversation.id)
        expect(conversation_ids).to include(restricted_conversation.id)
      end
    end

    context 'with assignee_type all' do
      let(:params) { { assignee_type: 'all' } }

      it 'filter conversations by assignee type all' do
        result = conversation_finder.perform
        expect(result[:conversations].length).to be 4
      end
    end

    context 'with assignee_type unassigned' do
      let(:params) { { assignee_type: 'unassigned' } }

      it 'filter conversations by assignee type unassigned' do
        result = conversation_finder.perform
        expect(result[:conversations].length).to be 1
      end
    end

    context 'with status all' do
      let(:params) { { status: 'all' } }

      it 'returns all conversations' do
        result = conversation_finder.perform
        expect(result[:conversations].length).to be 5
      end
    end

    context 'with assignee_type assigned' do
      let(:params) { { assignee_type: 'assigned' } }

      it 'filter conversations by assignee type assigned' do
        result = conversation_finder.perform
        expect(result[:conversations].length).to be 3
      end

      it 'returns the correct meta' do
        result = conversation_finder.perform
        # UniverZAP adds the Grupos tab, the Todos dropdown (Aguardando /
        # Em atendimento), and Resolvidas alongside the upstream four.
        expect(result[:count]).to eq({
                                       mine_count: 2,
                                       assigned_count: 3,
                                       unassigned_count: 1,
                                       all_count: 4,
                                       resolved_count: 1,
                                       group_count: 0,
                                       status_count: 0,
                                       waiting_count: 4,
                                       in_attendance_count: 0
                                     })
      end
    end

    context 'with status resolved' do
      let(:params) { { status: 'resolved' } }

      # UniverZAP: Resolvidas is its own dropdown view, picked by setting
      # status=resolved on the request. The Todos/Minhas/Aguardando/Em
      # atendimento badges must still reflect the open conversations — a
      # regression once had them collapse to the resolved-only counts
      # whenever the active view happened to be Resolvidas.
      it 'keeps the other badges scoped to open conversations' do
        result = conversation_finder.perform
        expect(result[:count]).to eq({
                                       mine_count: 2,
                                       assigned_count: 3,
                                       unassigned_count: 1,
                                       all_count: 4,
                                       resolved_count: 1,
                                       group_count: 0,
                                       status_count: 0,
                                       waiting_count: 4,
                                       in_attendance_count: 0
                                     })
      end
    end

    context 'with team' do
      let(:team) { create(:team, account: account) }
      let(:params) { { team_id: team.id } }

      it 'filter conversations by team' do
        create(:conversation, account: account, inbox: inbox, team: team)
        result = conversation_finder.perform
        expect(result[:conversations].length).to be 1
      end
    end

    context 'with labels' do
      let(:params) { { labels: ['resolved'] } }

      it 'filter conversations by labels' do
        conversation = inbox.conversations.first
        conversation.update_labels('resolved')

        result = conversation_finder.perform
        expect(result[:conversations].length).to be 1
      end
    end

    context 'with source_id' do
      let(:params) { { source_id: 'testing_source_id' } }

      it 'filter conversations by source id' do
        result = conversation_finder.perform
        expect(result[:conversations].length).to be 1
      end
    end

    context 'without source' do
      let(:params) { {} }

      it 'returns conversations with any source' do
        result = conversation_finder.perform
        expect(result[:conversations].length).to be 4
      end
    end

    context 'with updated_within' do
      let(:params) { { updated_within: 20, assignee_type: 'unassigned', sort_by: 'created_at_asc' } }

      it 'filters based on params, sort order but returns all conversations without pagination with in time range' do
        # value of updated_within is in seconds
        # write spec based on that
        conversations = create_list(:conversation, 50, account: account,
                                                       inbox: inbox, assignee: nil,
                                                       updated_at: Time.now.utc - 30.seconds,
                                                       created_at: Time.now.utc - 30.seconds)
        # update updated_at of 27 conversations to be with in 20 seconds
        conversations[0..27].each do |conversation|
          conversation.update(updated_at: Time.now.utc - 10.seconds)
        end
        result = conversation_finder.perform
        # pagination is not applied
        # filters are applied
        # modified conversations + 1 conversation created during set up
        expect(result[:conversations].length).to be 29
        # ensure that the conversations are sorted by created_at
        expect(result[:conversations].first.created_at).to be < result[:conversations].last.created_at
      end
    end

    context 'with pagination' do
      let(:params) { { status: 'open', assignee_type: 'me', page: 1 } }

      it 'returns paginated conversations' do
        create_list(:conversation, 50, account: account, inbox: inbox, assignee: user_1)
        result = conversation_finder.perform
        expect(result[:conversations].length).to be 25
      end
    end

    context 'with perform_meta_only' do
      let(:params) { { assignee_type: 'assigned' } }

      it 'returns only count without conversations' do
        result = conversation_finder.perform_meta_only
        expect(result).to have_key(:count)
        expect(result).not_to have_key(:conversations)
      end

      it 'returns the correct counts' do
        result = conversation_finder.perform_meta_only
        expect(result[:count]).to eq({
                                       mine_count: 2,
                                       assigned_count: 3,
                                       unassigned_count: 1,
                                       all_count: 4,
                                       resolved_count: 1,
                                       group_count: 0,
                                       status_count: 0,
                                       waiting_count: 4,
                                       in_attendance_count: 0
                                     })
      end

      it 'returns same counts as perform' do
        meta_result = conversation_finder.perform_meta_only
        full_result = conversation_finder.perform
        expect(meta_result[:count]).to eq(full_result[:count])
      end
    end

    context 'with unattended' do
      let(:params) { { status: 'open', assignee_type: 'me', conversation_type: 'unattended' } }

      it 'returns unattended conversations' do
        create(:conversation, account: account, first_reply_created_at: Time.now.utc, assignee: user_1) # attended_conversation
        create(:conversation, account: account, first_reply_created_at: nil, assignee: user_1) # unattended_conversation_no_first_reply
        create(:conversation, account: account, first_reply_created_at: Time.now.utc,
                              assignee: user_1, waiting_since: Time.now.utc) # unattended_conversation_waiting_since

        result = conversation_finder.perform
        expect(result[:conversations].length).to be 2
      end
    end

    context 'with attendance_state' do
      let!(:replied) do
        create(:conversation, account: account, inbox: inbox, assignee: user_1, first_reply_created_at: Time.current)
      end

      def bucket(attendance_state)
        described_class.new(user_1, { assignee_type: 'all', attendance_state: attendance_state }).perform[:conversations].map(&:id)
      end

      it 'splits Aguardando from Em atendimento by the first agent reply' do
        expect(bucket('in_attendance')).to eq([replied.id])
        expect(bucket('waiting')).not_to include(replied.id)
        expect(bucket('waiting').size).to eq(4)
      end

      it 'counts both views before narrowing the list' do
        count = described_class.new(user_1, { assignee_type: 'all', attendance_state: 'waiting' }).perform[:count]

        expect(count.slice(:waiting_count, :in_attendance_count)).to eq(waiting_count: 4, in_attendance_count: 1)
      end

      it 'narrows the route conversation_type instead of replacing it' do
        create(:mention, account: account, user: user_1, conversation: replied)
        params = { assignee_type: 'all', conversation_type: 'mention', attendance_state: 'waiting' }

        expect(described_class.new(user_1, params).perform[:conversations]).to be_empty
      end

      # UniverZAP: Aguardando is the fila de risco. A months-old thread where
      # our own broadcast was the last word must not outrank a contact who
      # wrote an hour ago and is still waiting on us, however the list is
      # sorted — so the contact-has-the-last-word flag comes before the sort.
      it 'puts whoever is waiting on us ahead of threads where we had the last word' do
        stale = create(:conversation, account: account, inbox: inbox, assignee: user_1,
                                      waiting_since: 30.days.ago, awaiting_reply: false)
        live = create(:conversation, account: account, inbox: inbox, assignee: user_1,
                                     waiting_since: 1.hour.ago, awaiting_reply: true)

        params = { assignee_type: 'all', attendance_state: 'waiting', sort_by: 'waiting_since_asc' }
        ids = described_class.new(user_1, params).perform[:conversations].map(&:id)

        expect(ids.index(live.id)).to be < ids.index(stale.id)
      end
    end

    context 'with created_on' do
      # 02:30 UTC on the 15th is still the 14th in São Paulo (UTC-3).
      let!(:late_night) do
        create(:conversation, account: account, inbox: inbox, assignee: user_1, created_at: Time.utc(2026, 10, 15, 2, 30))
      end

      before do
        create(:conversation, account: account, inbox: inbox, assignee: user_1, created_at: Time.utc(2026, 10, 15, 13, 0))
      end

      it 'lists only what started that day in the agent timezone, keeping the badges whole' do
        params = { assignee_type: 'all', created_on: '2026-10-14', timezone: 'America/Sao_Paulo' }
        result = described_class.new(user_1, params).perform

        expect(result[:conversations].map(&:id)).to eq([late_night.id])
        expect(result[:count][:all_count]).to be >= 2
      end

      it 'counts the conversations started per day' do
        params = { assignee_type: 'all', from: '2026-10-13', to: '2026-10-15', timezone: 'America/Sao_Paulo' }
        days = described_class.new(user_1, params).perform_created_per_day

        expect(days).to eq('2026-10-14' => 1, '2026-10-15' => 1)
      end
    end

    context 'with awaiting_reply' do
      let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: user_1) }

      it 'keeps who has the last word, ignoring notes, activities and automatic templates' do
        create(:message, conversation: conversation, message_type: :incoming)
        create(:message, conversation: conversation, message_type: :outgoing, private: true)
        create(:message, conversation: conversation, message_type: :activity)
        create(:message, conversation: conversation, message_type: :template)
        expect(conversation.reload.awaiting_reply).to be(true)

        create(:message, conversation: conversation, message_type: :outgoing, sender: nil)
        expect(conversation.reload.awaiting_reply).to be(false)
      end
    end

    context 'with whatsapp groups' do
      let!(:group_contact) { create(:contact, account: account, identifier: '120363000000000001@g.us') }
      let!(:group_conversation) do
        create(:conversation, account: account, inbox: inbox, assignee: user_1, contact: group_contact)
      end

      it 'flags is_group on create from the contact identifier' do
        expect(group_conversation.is_group).to be(true)
      end

      it 'returns only group conversations on the groups tab' do
        params = { assignee_type: 'all', conversation_type: 'groups', inbox_id: inbox.id }
        result = described_class.new(user_1, params).perform
        expect(result[:conversations].map(&:id)).to eq([group_conversation.id])
      end

      it 'excludes groups from regular tabs and counts them separately' do
        params = { assignee_type: 'all', inbox_id: inbox.id }
        result = described_class.new(user_1, params).perform
        expect(result[:conversations].map(&:id)).not_to include(group_conversation.id)
        expect(result[:count][:group_count]).to eq(1)
      end
    end

    context 'with whatsapp statuses' do
      let!(:status_conversation) do
        contact = create(:contact, account: account, identifier: 'status@broadcast')
        create(:conversation, account: account, inbox: inbox, assignee: user_1, contact: contact)
      end

      it 'shows the statuses only on their own tab and keeps them out of every other count', :aggregate_failures do
        expect(status_conversation.is_status_broadcast).to be(true)

        own = described_class.new(user_1, { assignee_type: 'all', conversation_type: 'status', inbox_id: inbox.id }).perform
        expect(own[:conversations].map(&:id)).to eq([status_conversation.id])

        regular = described_class.new(user_1, { assignee_type: 'all', inbox_id: inbox.id }).perform
        expect(regular[:conversations].map(&:id)).not_to include(status_conversation.id)
        expect(regular[:count]).to include(status_count: 1, all_count: account.conversations.regular.open.count)

        groups = described_class.new(user_1, { assignee_type: 'all', conversation_type: 'groups', inbox_id: inbox.id }).perform
        expect(groups[:conversations]).to be_empty
      end
    end
  end
end

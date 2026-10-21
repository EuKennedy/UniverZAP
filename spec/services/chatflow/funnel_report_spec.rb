require 'rails_helper'

RSpec.describe Chatflow::FunnelReport do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:chatflow) { Chatflow.create!(account: account, name: 'Funil', inbox: inbox, status: :active, trigger_type: :any_message) }
  let!(:menu) { flow_node(chatflow, :menu, 'text' => 'Quer agendar?', 'options' => [{ 'label' => 'Sim', 'value' => 'sim' }]) }
  let!(:done) { flow_node(chatflow, :end_flow, 'actions' => {}) }

  before do
    chatflow.update!(start_node: menu)
    flow_edge(menu, done, 'sim')
  end

  it 'conta quem entrou, quem está esperando e quem concluiu em cada etapa' do
    finished = create(:conversation, account: account, inbox: inbox)
    customer_says(finished, 'oi')
    customer_says(finished, '1')
    waiting = create(:conversation, account: account, inbox: inbox)
    customer_says(waiting, 'oi')
    dropped = create(:conversation, account: account, inbox: inbox)
    customer_says(dropped, 'oi')
    ChatflowExecution.find_by(conversation: dropped).update!(status: :aborted)

    report = described_class.new(chatflow).perform
    rows = report[:nodes].index_by { |row| row[:node_id] }

    expect(report[:totals]).to include(started: 3, completed: 1, aborted: 1, live: 1)
    expect(rows[menu.id]).to include(entered: 3, waiting: 1, dropped: 1, advanced: 1)
    expect(rows[done.id]).to include(entered: 1, completed: 1, dropped: 0)
  end
end

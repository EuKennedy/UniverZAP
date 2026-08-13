require 'rails_helper'

RSpec.describe Ai::Belezaki::Connection do
  let(:account) { create(:account) }
  let(:assistant) { create(:ai_assistant, account: account) }

  def connect!(status: 'active')
    described_class.create!(
      ai_assistant: assistant, account: account, external_id: 'ext-1',
      salon_name: 'Studio Bella', timezone: 'America/Sao_Paulo', status: status,
      connected_at: Time.current
    )
  end

  it 'answers belezaki as the agenda provider once connected' do
    connect!

    expect(assistant.reload.agenda_provider).to eq(:belezaki)
  end

  # One agenda per agent is the product rule AND a payload rule: two connections
  # would put two tools called `consultar_horarios` in the same request.
  it 'refuses a second connection for the same agent' do
    connect!

    expect { connect! }.to raise_error(ActiveRecord::RecordInvalid)
  end

  # A revoked row must not keep the agent scheduling against an agenda it can no
  # longer reach.
  it 'is not a provider once revoked' do
    connect!(status: 'revoked')

    expect(assistant.reload.agenda_provider).to be_nil
  end

  it 'names the salon so the screen can say which one' do
    expect(connect!.push_event_data).to include(salon_name: 'Studio Bella', status: 'active')
  end

  it 'records why the agenda stopped' do
    connection = connect!

    connection.revoke!('token rejected')

    expect(connection).not_to be_active
    expect(connection.last_error).to eq('token rejected')
  end

  # Deleting an agent used to trip over foreign keys twice; the association is
  # :destroy for exactly that reason.
  it 'goes away with the agent' do
    connect!

    expect { assistant.destroy! }.to change(described_class, :count).by(-1)
  end
end

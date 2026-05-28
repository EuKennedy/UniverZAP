require 'rails_helper'

RSpec.describe AccountTasksChannel do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }

  before { stub_connection }

  it 'subscribes to per-account + per-user task streams when the user belongs to the account' do
    subscribe(account_id: account.id, user_id: user.id, pubsub_token: user.pubsub_token)
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_for("account_#{account.id}_tasks")
    expect(subscription).to have_stream_for("account_#{account.id}_user_#{user.id}_tasks")
  end

  it 'rejects subscribers that do not belong to the requested account' do
    other_account = create(:account)
    subscribe(account_id: other_account.id, user_id: user.id, pubsub_token: user.pubsub_token)
    expect(subscription).to be_rejected
  end

  it 'rejects requests with a mismatched pubsub_token' do
    subscribe(account_id: account.id, user_id: user.id, pubsub_token: 'wrong')
    expect(subscription).to be_rejected
  end
end

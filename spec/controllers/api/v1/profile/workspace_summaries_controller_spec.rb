require 'rails_helper'

RSpec.describe 'Workspace summaries API', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }

  before do
    create(:account_user, account: other_account, user: user)
    create_list(:notification, 2, account: account, user: user)
    create(:notification, account: account, user: user, read_at: Time.current)
    create(:notification, account: account, user: user, snoozed_until: 1.day.from_now)
    create(:notification, account: account, user: create(:user, account: account))
  end

  it 'counts the unread notifications of the user in each account' do
    get '/api/v1/profile/workspace_summary', headers: user.create_new_auth_token, as: :json

    expect(response.parsed_body['payload']).to contain_exactly(
      { 'account_id' => account.id, 'unread_notifications_count' => 2 },
      { 'account_id' => other_account.id, 'unread_notifications_count' => 0 }
    )
  end

  it 'requires a signed-in user' do
    get '/api/v1/profile/workspace_summary', as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end

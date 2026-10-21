require 'rails_helper'

RSpec.describe 'Scheduled messages API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:outsider) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:base) { "/api/v1/accounts/#{account.id}/scheduled_messages" }

  before { create(:inbox_member, user: agent, inbox: inbox) }

  it 'agenda, lista, edita e cancela' do
    payload = { content: 'Oi {primeiro_nome}', send_at: 1.day.from_now.iso8601 }
    post base, params: { conversation_id: conversation.display_id, scheduled_message: payload }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    id = response.parsed_body['id']
    expect(response.parsed_body).to include('status' => 'scheduled', 'cancel_if_reply' => true, 'conversation_id' => conversation.display_id)

    patch "#{base}/#{id}", params: { scheduled_message: { content: 'Oi de novo' } }, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['content']).to eq('Oi de novo')

    delete "#{base}/#{id}", headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('status' => 'cancelled', 'cancel_reason' => 'manual')

    get base, params: { conversation_id: conversation.display_id }, headers: agent.create_new_auth_token
    expect(response.parsed_body['payload'].pluck('status')).to eq(['cancelled'])
  end

  it 'recusa horário no passado' do
    post base, params: { conversation_id: conversation.display_id, scheduled_message: { content: 'Oi', send_at: 1.hour.ago.iso8601 } },
               headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'não deixa editar o que já saiu' do
    sent = create(:scheduled_message, conversation: conversation, status: :sent)

    patch "#{base}/#{sent.id}", params: { scheduled_message: { content: 'x' } }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'agente sem acesso à caixa não vê a conversa' do
    get base, params: { conversation_id: conversation.display_id }, headers: outsider.create_new_auth_token

    expect(response).to have_http_status(:unauthorized)
  end

  it 'sugere o melhor horário' do
    get "#{base}/best_time", params: { conversation_id: conversation.display_id }, headers: agent.create_new_auth_token

    expect(response.parsed_body).to eq('hour' => nil, 'at' => nil)
  end
end

require 'rails_helper'

RSpec.describe 'Message sequences API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/message_sequences" }
  let(:steps) { [{ offset_minutes: -1440, text: 'Lembrete: amanhã às {servico}' }] }

  it 'nasce desligada' do
    post base, params: { message_sequence: { name: 'Lembrete', steps: steps } }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to include('enabled' => false, 'pending_count' => 0)
  end

  it 'desligar cancela o que estava pendente' do
    sequence = create(:message_sequence, account: account, enabled: true)
    scheduled = create(:scheduled_message, message_sequence: sequence, conversation: create(:conversation, account: account))

    patch "#{base}/#{sequence.id}", params: { message_sequence: { enabled: false } }, headers: admin.create_new_auth_token, as: :json

    expect(scheduled.reload).to have_attributes(status: 'cancelled', cancel_reason: 'sequence_disabled')
  end

  it 'agente não cria sequência' do
    post base, params: { message_sequence: { name: 'x', steps: steps } }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'recusa passo sem texto' do
    post base, params: { message_sequence: { name: 'x', steps: [{ offset_minutes: 60, text: '' }] } }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end
end

require 'rails_helper'

RSpec.describe 'Conversation schedule API', type: :request do
  let(:account) { create(:account, custom_attributes: { 'vertical_template' => 'beauty_salon' }) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :open) }
  let(:params) { { servico: 'Corte', profissional: 'Ana', data_agendamento: '2026-10-25T14:00:00.000Z', ciclo_recompra_semanas: '4' } }

  before do
    vertical = Vertical.create!(key: 'beauty_salon', name: 'Salão de beleza')
    vertical.vertical_statuses.create!(title: 'novo-contato', position: 1, color: '#94A3B8')
    vertical.vertical_statuses.create!(title: 'agendado', position: 2, color: '#14B8A6')
    %w[novo-contato agendado lead-anuncio].each { |title| create(:label, account: account, title: title) }
    create(:inbox_member, user: agent, inbox: inbox)
  end

  describe 'POST /api/v1/accounts/{account.id}/conversations/{id}/schedule' do
    it 'returns unauthorized without a user' do
      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/schedule", params: params, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'saves the appointment, swaps the stage for agendado and returns both' do
      conversation.update!(label_list: %w[novo-contato lead-anuncio])

      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/schedule",
           params: params, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['custom_attributes']).to include('servico' => 'Corte', 'profissional' => 'Ana',
                                                   'data_agendamento' => '2026-10-25T14:00:00.000Z', 'ciclo_recompra_semanas' => '4')
      expect(body['labels']).to contain_exactly('lead-anuncio', 'agendado')
      expect(conversation.reload.label_list).to contain_exactly('lead-anuncio', 'agendado')
    end

    it 'is refused for a vertical without scheduling, like e-commerce' do
      account.update!(custom_attributes: { 'vertical_template' => 'ecommerce' })

      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/schedule",
           params: params, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(conversation.reload.label_list).not_to include('agendado')
    end

    it 'is not found for a conversation of another account' do
      other = create(:conversation, account: create(:account))

      post "/api/v1/accounts/#{account.id}/conversations/#{other.display_id}/schedule",
           params: params, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end

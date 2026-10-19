require 'rails_helper'

RSpec.describe 'Vertical statuses API', type: :request do
  let!(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  before do
    %w[novo-contato agendado lead-anuncio].each { |title| create(:label, account: account, title: title) }
  end

  describe 'GET /api/v1/accounts/{account.id}/vertical_statuses' do
    it 'returns unauthorized without a user' do
      get "/api/v1/accounts/#{account.id}/vertical_statuses"

      expect(response).to have_http_status(:unauthorized)
    end

    it 'shows the labels an admin picked for the bar, in the picked order' do
      account.update!(custom_attributes: { 'conversation_bar_labels' => %w[lead-anuncio agendado] })

      get "/api/v1/accounts/#{account.id}/vertical_statuses", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['statuses'].pluck('title')).to eq(%w[lead-anuncio agendado])
    end

    it 'serves an agent their own bar when titles are asked for, over the account pick' do
      account.update!(custom_attributes: { 'conversation_bar_labels' => %w[agendado] })

      get "/api/v1/accounts/#{account.id}/vertical_statuses",
          params: { titles: %w[lead-anuncio novo-contato] },
          headers: agent.create_new_auth_token,
          as: :json

      expect(response.parsed_body['statuses'].pluck('title')).to eq(%w[lead-anuncio novo-contato])
    end

    it 'skips picked titles that no longer exist as labels' do
      account.update!(custom_attributes: { 'conversation_bar_labels' => %w[agendado apagada] })

      get "/api/v1/accounts/#{account.id}/vertical_statuses", headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body['statuses'].pluck('title')).to eq(%w[agendado])
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/vertical_statuses/catalog' do
    it 'lists every label with its open count, most used first' do
      tagged = create(:conversation, account: account)
      tagged.update_labels(%w[agendado])
      create(:conversation, account: account, status: :resolved).update_labels(%w[agendado novo-contato])

      get "/api/v1/accounts/#{account.id}/vertical_statuses/catalog", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      labels = response.parsed_body['labels']
      expect(labels.first).to include('title' => 'agendado', 'count' => 1)
      expect(labels.pluck('title')).to match_array(%w[agendado lead-anuncio novo-contato])
      expect(labels.find { |l| l['title'] == 'novo-contato' }['count']).to eq(0)
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/vertical_statuses/selection' do
    it 'lets an admin choose the labels and drops unknown ones' do
      patch "/api/v1/accounts/#{account.id}/vertical_statuses/selection",
            params: { titles: %w[agendado inexistente lead-anuncio] },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:no_content)
      expect(account.reload.custom_attributes['conversation_bar_labels']).to eq(%w[agendado lead-anuncio])
    end

    it 'goes back to the vertical default when the list is emptied' do
      account.update!(custom_attributes: { 'conversation_bar_labels' => %w[agendado] })

      patch "/api/v1/accounts/#{account.id}/vertical_statuses/selection",
            params: { titles: [] },
            headers: admin.create_new_auth_token,
            as: :json

      expect(account.reload.custom_attributes['conversation_bar_labels']).to eq([])
    end

    it 'refuses an agent' do
      patch "/api/v1/accounts/#{account.id}/vertical_statuses/selection",
            params: { titles: %w[agendado] },
            headers: agent.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Ai::ResponseFeedbacksController', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:invocation) do
    create(:ai_invocation, account: account, ai_assistant: assistant, phase: 'autopilot',
                           user_message: 'quanto custa a progressiva?', ai_response: 'Fica R$ 999,00.')
  end
  let(:path) do
    "/api/v1/accounts/#{account.id}/ai/assistants/#{assistant.id}/responses/#{invocation.id}/feedback"
  end

  def post_feedback(payload, user: admin)
    post path, params: { feedback: payload }, headers: user.create_new_auth_token, as: :json
  end

  describe 'authorisation' do
    it 'rejects an unauthenticated request' do
      post path, params: { feedback: { rating: 'up' } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    # The log carries customer text and the correction rewrites the agent's
    # knowledge, so this is admin territory.
    it 'rejects a non-administrator' do
      post_feedback({ rating: 'up' }, user: agent)

      expect(response).to have_http_status(:unauthorized)
    end

    it 'refuses an agent from another account' do
      foreign = create(:ai_assistant, account: create(:account))

      post "/api/v1/accounts/#{account.id}/ai/assistants/#{foreign.id}/responses/#{invocation.id}/feedback",
           params: { feedback: { rating: 'up' } }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'rating' do
    it 'records a thumbs up' do
      post_feedback({ rating: 'up' })

      expect(response).to have_http_status(:ok)
      expect(invocation.response_feedbacks.first.rating).to eq('up')
    end

    # Clicking twice must not stack votes, or the approval rate becomes a
    # number the operator can inflate by accident.
    it 'replaces the reviewer own earlier verdict instead of stacking' do
      post_feedback({ rating: 'up' })
      post_feedback({ rating: 'ideal' })

      expect(invocation.response_feedbacks.count).to eq(1)
      expect(invocation.response_feedbacks.first.rating).to eq('ideal')
    end

    it 'refuses a thumbs down with no reason' do
      post_feedback({ rating: 'down' })

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'a correction takes effect immediately' do
    it 'turns the correction into knowledge on the way in' do
      expect do
        post_feedback({ rating: 'down', reason: 'preco_inventado',
                        corrected_text: 'A progressiva fica R$ 189,90.' })
      end.to change { assistant.trainings.count }.by(1)

      body = response.parsed_body
      expect(body['applied']).to be(true)
      expect(assistant.trainings.last.content).to include('R$ 189,90')
    end

    it 'records a tone correction without applying it' do
      expect do
        post_feedback({ rating: 'down', reason: 'tom_inadequado', corrected_text: 'Seja mais direto.' })
      end.not_to(change { assistant.trainings.count })

      expect(response.parsed_body['applied']).to be(false)
    end

    it 'does not create a second document when the same verdict is sent twice' do
      payload = { rating: 'down', reason: 'info_incorreta', corrected_text: 'O certo é 189,90.' }
      post_feedback(payload)

      expect { post_feedback(payload) }.not_to(change { assistant.trainings.count })
    end
  end
end

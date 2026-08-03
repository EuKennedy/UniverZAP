# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Ai::AssistantTemplatesController', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  describe 'the picker' do
    it 'lists a template per vertical' do
      get "/api/v1/accounts/#{account.id}/ai/assistant_templates",
          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['templates'].pluck('key'))
        .to contain_exactly('salao', 'clinica', 'nails', 'varejo')
    end

    # The picker needs enough to choose, not the whole prompt.
    it 'keeps the full prompt out of the list' do
      get "/api/v1/accounts/#{account.id}/ai/assistant_templates",
          headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['templates'].first).not_to have_key('system_prompt')
    end

    it 'returns the whole template on show' do
      get "/api/v1/accounts/#{account.id}/ai/assistant_templates/varejo",
          headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['system_prompt']).to be_present
    end

    it '404s on an unknown template instead of failing loudly' do
      get "/api/v1/accounts/#{account.id}/ai/assistant_templates/inexistente",
          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'creating an agent from a template' do
    def create_agent(payload)
      post "/api/v1/accounts/#{account.id}/ai/assistants",
           params: payload, headers: admin.create_new_auth_token, as: :json
    end

    # An agent with instructions and an empty knowledge base has nothing it is
    # allowed to assert, so it deflects every question and the operator
    # concludes the AI does not work.
    it 'seeds the starter documents' do
      expect { create_agent({ ai_assistant: { name: 'Téo' }, template: 'varejo' }) }
        .to change { Ai::Training.count }.by(2)

      expect(Ai::Training.pluck(:status).uniq).to eq(['ready'])
    end

    it 'fills the instructions from the vertical' do
      create_agent({ ai_assistant: { name: 'Téo' }, template: 'varejo' })

      expect(Ai::Assistant.last.system_prompt).to include('descobrir o uso real')
    end

    # Someone who typed a name and then picked a vertical must not lose what
    # they typed.
    it 'never overwrites what the operator already wrote' do
      create_agent(
        { ai_assistant: { name: 'Téo', system_prompt: 'Minhas instruções.' }, template: 'varejo' }
      )

      expect(Ai::Assistant.last.system_prompt).to eq('Minhas instruções.')
    end

    it 'creates a plain agent when no template is picked' do
      expect { create_agent({ ai_assistant: { name: 'Téo' } }) }
        .not_to(change { Ai::Training.count })
    end

    it 'ignores an unknown template instead of failing the creation' do
      create_agent({ ai_assistant: { name: 'Téo' }, template: 'inexistente' })

      expect(response).to have_http_status(:ok)
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Ai::ManagerController', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:assistant) { create(:ai_assistant, account: account, name: 'Marina') }
  let(:base) { "/api/v1/accounts/#{account.id}/ai/manager" }
  let(:suggestion) { create(:ai_manager_suggestion, ai_assistant: assistant) }

  def as(user)
    user.create_new_auth_token
  end

  describe 'GET overview' do
    # Regressão explícita: o `check_authorization` herdado deriva o model do
    # nome da controller, "manager" viraria a classe `Manager`, e a requisição
    # morreria como NameError antes de qualquer permissão ser consultada. Já
    # derrubou um painel inteiro nesta base.
    it 'responde sem explodir na derivação de model da controller' do
      get "#{base}/overview", headers: as(administrator), as: :json

      expect(response).to have_http_status(:success)
    end

    it 'devolve as três notas, os agentes e o estado da amostra' do
      assistant
      get "#{base}/overview", headers: as(administrator), as: :json

      body = response.parsed_body
      expect(body['scores'].keys).to contain_exactly('reliability', 'conversion', 'cost')
      expect(body['agents'].map { |row| row['name'] }).to include('Marina')
      expect(body['data_sufficiency']).to include('enough' => false, 'needed' => 20)
    end

    it 'recusa quem não está autenticado' do
      get "#{base}/overview", as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'nunca responde por uma conta em que a pessoa não está' do
      stranger = create(:user, account: create(:account), role: :administrator)

      get "#{base}/overview", headers: as(stranger), as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET suggestions' do
    it 'lista a fila da conta' do
      suggestion
      get "#{base}/suggestions", params: { status: 'pending' }, headers: as(administrator), as: :json

      payload = response.parsed_body['payload']
      expect(payload.length).to eq(1)
      expect(payload.first).to include('check_key' => 'loose_promise', 'agent_name' => 'Marina')
      expect(payload.first['evidence']).to include('conversation_id', 'excerpt', 'metric', 'value')
    end

    it 'filtra pelo estado pedido' do
      suggestion
      get "#{base}/suggestions", params: { status: 'dismissed' }, headers: as(administrator), as: :json

      expect(response.parsed_body['payload']).to be_empty
    end

    # A fila da conta vem junto de propósito. Com a lista vazia dos dois lados,
    # este exemplo passaria igual se o endpoint tivesse parado de devolver
    # qualquer coisa, e o que ele precisa provar é que o filtro por conta é o
    # que deixou a outra de fora.
    it 'nunca vaza a sugestão de outra conta' do
      suggestion
      create(:ai_manager_suggestion, ai_assistant: create(:ai_assistant, account: create(:account)))

      get "#{base}/suggestions", headers: as(administrator), as: :json

      payload = response.parsed_body['payload']
      expect(payload.length).to eq(1)
      expect(payload.first['agent_name']).to eq('Marina')
    end

    # Quem abre a tela tem cinco minutos, e a lista sai cortada em
    # MAX_SUGGESTIONS. Ordenada por data, o horário prometido errado seria
    # exatamente o cartão que ficaria de fora do corte.
    it 'coloca o mais grave no topo da fila' do
      suggestion
      create(:ai_manager_suggestion, ai_assistant: assistant, check_key: 'promised_time_mismatch',
                                     severity: 'critical')

      get "#{base}/suggestions", headers: as(administrator), as: :json

      expect(response.parsed_body['payload'].map { |row| row['severity'] }).to eq(%w[critical high])
    end
  end

  describe 'POST approve' do
    it 'aplica e diz no que a sugestão virou' do
      post "#{base}/suggestions/#{suggestion.id}/approve", headers: as(administrator), as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['status']).to eq('applied')
      expect(response.parsed_body['applied_as']['type']).to eq('prompt_version')
    end

    # A regra mais importante desta base, no caminho de escrita: aprovar uma
    # sugestão muda o que um agente fala com cliente.
    it 'devolve 404 para a sugestão de outra conta' do
      stranger = create(:ai_manager_suggestion, ai_assistant: create(:ai_assistant, account: create(:account)))

      post "#{base}/suggestions/#{stranger.id}/approve", headers: as(administrator), as: :json

      expect(response).to have_http_status(:not_found)
      expect(stranger.reload.status).to eq('pending')
    end

    it 'recusa quem não é administrador' do
      post "#{base}/suggestions/#{suggestion.id}/approve", headers: as(agent), as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(suggestion.reload.status).to eq('pending')
    end

    # A camada de cima, provada sozinha. Hoje quem não é administrador já para
    # na ReportPolicy, então o exemplo acima não diz nada sobre o `ensure_admin`
    # e continuaria verde se alguém o apagasse. ReportPolicy é extensível por
    # enterprise, e é este before_action que segura a escrita no dia em que
    # a leitura for afrouxada.
    it 'exige administrador mesmo quando a política de leitura libera' do
      allow(ReportPolicy).to receive(:new).and_return(instance_double(ReportPolicy, view?: true))

      post "#{base}/suggestions/#{suggestion.id}/approve", headers: as(agent), as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(suggestion.reload.status).to eq('pending')
    end
  end

  describe 'POST dismiss' do
    it 'dispensa guardando o motivo' do
      post "#{base}/suggestions/#{suggestion.id}/dismiss", params: { reason: 'a gente faz assim de propósito' },
                                                           headers: as(administrator), as: :json

      expect(response.parsed_body['status']).to eq('dismissed')
      expect(suggestion.reload.dismissed_reason).to eq('a gente faz assim de propósito')
    end

    it 'não dispensa o que já foi decidido' do
      suggestion.update!(status: 'applied', applied_at: Time.current)

      post "#{base}/suggestions/#{suggestion.id}/dismiss", headers: as(administrator), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'recusa quem não é administrador' do
      post "#{base}/suggestions/#{suggestion.id}/dismiss", headers: as(agent), as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'devolve 404 para a sugestão de outra conta' do
      stranger = create(:ai_manager_suggestion, ai_assistant: create(:ai_assistant, account: create(:account)))

      post "#{base}/suggestions/#{stranger.id}/dismiss", headers: as(administrator), as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'as rodadas' do
    it 'estima antes de rodar, e a v1 não cobra nada' do
      get "#{base}/runs/estimate", headers: as(administrator), as: :json

      expect(response.parsed_body).to include('credits_cents_brl' => 0, 'conversations' => 0)
    end

    it 'roda sob demanda e devolve a rodada' do
      post "#{base}/runs", headers: as(administrator), as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['run_id']).to be_present
      expect(Ai::Manager::Run.find(response.parsed_body['run_id']).triggered_by).to eq('manual')
    end

    it 'recusa quem não é administrador' do
      expect do
        post "#{base}/runs", headers: as(agent), as: :json
      end.not_to change(Ai::Manager::Run, :count)

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'o catálogo de verificações' do
    it 'expõe as quatro com o que cada uma mede' do
      get "#{base}/checks", headers: as(administrator), as: :json

      payload = response.parsed_body['payload']
      expect(payload.length).to eq(Ai::Manager::Checks.all.length)
      expect(payload.first.keys).to include('key', 'title', 'what_it_measures', 'enabled')
      expect(payload.map { |row| row['enabled'] }.uniq).to eq([true])
    end

    it 'desliga uma verificação para esta conta' do
      patch "#{base}/checks/loose_promise", params: { enabled: false }, headers: as(administrator), as: :json

      expect(response.parsed_body).to eq('key' => 'loose_promise', 'enabled' => false)
      expect(Ai::Manager::CheckSetting.disabled_keys_for(account)).to include('loose_promise')
    end

    it 'devolve 404 para uma verificação que não existe' do
      patch "#{base}/checks/inventada", params: { enabled: false }, headers: as(administrator), as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'recusa quem não é administrador' do
      patch "#{base}/checks/loose_promise", params: { enabled: false }, headers: as(agent), as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(Ai::Manager::CheckSetting.count).to be_zero
    end
  end
end

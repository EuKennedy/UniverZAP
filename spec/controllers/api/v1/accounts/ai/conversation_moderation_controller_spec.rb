# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Ai::ConversationModerationController', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/ai/manager/conversations" }

  def as(user)
    user.create_new_auth_token
  end

  describe 'GET index' do
    # Regressão explícita, herdada do Gerente: o `check_authorization` da base
    # deriva o model do nome da controller, e a requisição morreria como
    # NameError antes de qualquer permissão ser consultada.
    it 'responde sem explodir na derivação de model da controller' do
      get base, headers: as(administrator), as: :json

      expect(response).to have_http_status(:success)
    end

    it 'devolve os achados, as contagens e as janelas que a tela pode oferecer' do
      create(:ai_manager_conversation_finding, account: account, case_key: 'cliente_esperando')

      get base, headers: as(administrator), as: :json

      body = response.parsed_body
      expect(body['findings'].pluck('case_key')).to eq(['cliente_esperando'])
      expect(body['counts']).to include('total' => 1)
      expect(body['windows']).to eq([1, 3, 7, 30])
    end

    # Administrador só, pela mesma porta de Relatórios (ReportPolicy#view?).
    #
    # Cheguei aqui achando que quem atende deveria ver, já que é quem responde.
    # Está errado: um atendente pode estar restrito a uma caixa de entrada, e
    # esta lista é da conta inteira, com trecho de mensagem de cliente junto.
    # Liberá-la daria a ele o conteúdo de conversas que ele não pode abrir.
    it 'recusa quem atende, porque a lista é da conta inteira e carrega trecho de conversa' do
      get base, headers: as(agent), as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'recusa quem não está autenticado' do
      get base, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'nunca responde por uma conta em que a pessoa não está' do
      stranger = create(:user, account: create(:account), role: :administrator)

      get base, headers: as(stranger), as: :json

      expect(response).to have_http_status(:not_found).or have_http_status(:unauthorized)
    end

    it 'filtra por autor sem tocar em modelo nenhum' do
      create(:ai_manager_conversation_finding, account: account, author: 'agent', case_key: 'agente_repetiu')
      create(:ai_manager_conversation_finding, account: account, author: 'human', case_key: 'compra_travada',
                                               conversation_id: 999)

      get base, params: { author: 'human' }, headers: as(administrator), as: :json

      expect(response.parsed_body['findings'].pluck('case_key')).to eq(['compra_travada'])
    end
  end

  describe 'GET estimate' do
    it 'diz o preço antes de qualquer coisa ser lida' do
      get "#{base}/estimate", params: { hours: 24 }, headers: as(administrator), as: :json

      body = response.parsed_body
      expect(body).to include('will_read', 'cost_cents_brl', 'candidates')
      expect(body['window_hours']).to eq(24)
    end

    # Uma janela livre deixaria alguém pedir um ano e derrubar a varredura no
    # timeout. Fora da lista, cai no padrão em vez de obedecer.
    it 'ignora janela que não existe e cai no padrão de sete dias' do
      get "#{base}/estimate", params: { hours: 9999 }, headers: as(administrator), as: :json

      expect(response.parsed_body['window_hours']).to eq(168)
    end
  end

  describe 'POST scans' do
    it 'cria a varredura e devolve o id para a tela acompanhar' do
      expect do
        post "#{base}/scans", params: { hours: 72 }, headers: as(administrator), as: :json
      end.to change(Ai::Manager::ConversationScan, :count).by(1)

      expect(response.parsed_body).to include('status' => 'running', 'window_hours' => 72)
    end

    it 'enfileira a leitura em vez de segurar a requisição por minutos' do
      expect do
        post "#{base}/scans", headers: as(administrator), as: :json
      end.to have_enqueued_job(Ai::Manager::ConversationScanJob)
    end

    # Proteção de dinheiro e não de banco: duas varreduras simultâneas leem as
    # mesmas conversas e cobram duas vezes pelo mesmo resultado.
    it 'devolve a que já está rodando em vez de abrir e cobrar outra' do
      running = create(:ai_manager_conversation_scan, account: account, status: 'running')

      expect do
        post "#{base}/scans", headers: as(administrator), as: :json
      end.not_to change(Ai::Manager::ConversationScan, :count)

      expect(response.parsed_body).to include('id' => running.id, 'already_running' => true)
    end

    # Gastar crédito muda a fatura do operador, então passa pela mesma régua que
    # aprovar uma sugestão do Gerente.
    it 'recusa quem não é administrador, porque isto gasta crédito' do
      post "#{base}/scans", headers: as(agent), as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET scans/:id' do
    it 'devolve o andamento para a tela parar de perguntar quando acabar' do
      scan = create(:ai_manager_conversation_scan, :done, account: account)

      get "#{base}/scans/#{scan.id}", headers: as(administrator), as: :json

      expect(response.parsed_body).to include('status' => 'done', 'conversations_read' => 43)
    end

    # A varredura SEMPRE sai da conta autenticada. É esta linha que faz a
    # varredura de outra conta devolver 404 em vez de vazar o custo dela.
    it 'nunca devolve varredura de outra conta' do
      stranger = create(:ai_manager_conversation_scan, account: create(:account))

      get "#{base}/scans/#{stranger.id}", headers: as(administrator), as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST scans com uma varredura pendurada' do
    # Job morto com o worker, ou deploy passando por cima dele: a linha fica
    # 'running' para sempre, o botão de analisar some da aba e a conta perde a
    # feature, sem nada na tela que a destrave.
    it 'destrava a conta e começa uma nova' do
      velha = create(:ai_manager_conversation_scan, account: account, status: 'running',
                                                    created_at: 2.hours.ago)

      expect do
        post "#{base}/scans", headers: as(administrator), as: :json
      end.to change(Ai::Manager::ConversationScan, :count).by(1)

      expect(velha.reload.status).to eq('failed')
      expect(response.parsed_body).to include('status' => 'running')
    end

    it 'conta o que aconteceu com a que ficou pendurada, em vez de apagá-la' do
      velha = create(:ai_manager_conversation_scan, account: account, status: 'running',
                                                    created_at: 2.hours.ago)

      post "#{base}/scans", headers: as(administrator), as: :json

      expect(velha.reload.summary['error']).to include('interrompida')
    end

    # A recém-começada continua protegida: o segundo clique não pode cobrar de novo.
    it 'ainda protege a que começou agora' do
      create(:ai_manager_conversation_scan, account: account, status: 'running')

      expect do
        post "#{base}/scans", headers: as(administrator), as: :json
      end.not_to change(Ai::Manager::ConversationScan, :count)
    end
  end
end

require 'rails_helper'

RSpec.describe Ai::Wiki::Tools do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:tools) { described_class.new(account: account, user: admin) }

  def answer(name, input = {})
    JSON.parse(tools.call(name, input))
  end

  describe 'fila_de_conversas' do
    it 'conta abertas, sem primeira resposta, sem responsável e pendentes' do
      create(:conversation, account: account, status: :open, first_reply_created_at: nil, assignee: nil)
      create(:conversation, account: account, status: :pending)

      expect(answer('fila_de_conversas'))
        .to include('abertas' => 1, 'sem_primeira_resposta' => 1, 'sem_responsavel' => 1, 'pendentes' => 1)
    end

    # O playground cria conversa de mentira; contá-la faz a conta se ver maior
    # do que é, e o operador procurar um atendimento que nunca existiu.
    it 'não conta a conversa de sandbox do playground' do
      create(:conversation, account: account, status: :open,
                            additional_attributes: { 'athenas_sandbox' => true })

      expect(answer('fila_de_conversas')['abertas']).to eq(0)
    end
  end

  describe 'analise_das_conversas' do
    it 'diz quando nunca rodou, em vez de inventar que está tudo bem' do
      expect(answer('analise_das_conversas')).to include('analise_nunca_rodou' => true)
    end

    it 'marca como desatualizada a leitura de ontem' do
      create(:ai_manager_conversation_scan, account: account, status: 'done',
                                            finished_at: 3.days.ago, window_hours: 24)

      expect(answer('analise_das_conversas')).to include('analise_desatualizada' => true)
    end

    it 'não marca como desatualizada a leitura de agora' do
      create(:ai_manager_conversation_scan, account: account, status: 'done',
                                            finished_at: 10.minutes.ago, window_hours: 24)

      expect(answer('analise_das_conversas')).to include('analise_desatualizada' => false)
    end
  end

  describe 'rodar_analise' do
    # A única ferramenta que gasta: ela chama modelo uma vez por conversa lida.
    it 'dispara a varredura na janela pedida' do
      expect { answer('rodar_analise', 'janela_horas' => 72) }
        .to have_enqueued_job(Ai::Manager::ConversationScanJob)

      expect(account.ai_manager_conversation_scans.last.window_hours).to eq(72)
    end

    it 'cai na janela padrão quando o modelo inventa um número' do
      answer('rodar_analise', 'janela_horas' => 999)

      expect(Ai::Manager::ConversationScan::WINDOWS)
        .to include(account.ai_manager_conversation_scans.last.window_hours)
    end

    # Mesma regra do botão da tela: gastar crédito da conta é coisa de admin.
    it 'recusa quem não é administrador' do
      atendente = described_class.new(account: account, user: agent)

      expect { atendente.call('rodar_analise', 'janela_horas' => 24) }
        .not_to(change { account.ai_manager_conversation_scans.count })
    end

    it 'nem oferece a ferramenta para quem não pode usá-la' do
      atendente = described_class.new(account: account, user: agent)

      expect(atendente.definitions.pluck(:name)).not_to include('rodar_analise')
      expect(tools.definitions.pluck(:name)).to include('rodar_analise')
    end

    # Duas varreduras simultâneas leem as mesmas conversas e cobram duas vezes
    # pelo mesmo resultado.
    it 'devolve a que já está rodando em vez de abrir outra' do
      create(:ai_manager_conversation_scan, account: account, status: 'running', window_hours: 24)

      expect { answer('rodar_analise', 'janela_horas' => 24) }
        .not_to(change { account.ai_manager_conversation_scans.count })
    end

    it 'marca o turno como escrita, para ele não ser repetido' do
      answer('rodar_analise', 'janela_horas' => 24)

      expect(tools.performed_write?).to be(true)
    end
  end

  # Uma consulta que falha não pode virar tela de erro para quem só perguntou
  # uma coisa.
  it 'devolve dado, e não exceção, quando a consulta quebra' do
    allow(Ai::Manager::Conversations::Listing).to receive(:new).and_raise(StandardError, 'banco fora')

    expect(answer('analise_das_conversas')).to have_key('erro')
  end

  it 'responde a uma ferramenta que não existe sem explodir' do
    expect(answer('ferramenta_inventada')).to have_key('erro')
  end
end

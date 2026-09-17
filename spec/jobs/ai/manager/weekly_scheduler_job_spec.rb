require 'rails_helper'

RSpec.describe Ai::Manager::WeeklySchedulerJob do
  # Conta nasce com um agente semeado (Account after_create_commit), então
  # desligar TODOS é o que monta o caso do salão visto em produção.
  def account_with_all_agents_off
    account = create(:account)
    account.ai_assistants.find_each { |assistant| assistant.update!(active: false) }
    account
  end

  it 'enfileira uma rodada por conta que tem agente' do
    account = create(:account)

    expect { described_class.perform_now }
      .to have_enqueued_job(Ai::Manager::AnalysisJob).with(account.id, 'schedule')
  end

  # O furo que Ai::Manager::AnalysisService#audited_assistants documenta, refeito
  # um nível acima: filtrar por `active` aqui fazia a conta não ter rodada
  # nenhuma, e a tela não conseguia distinguir "não achei nada" de "nunca fui
  # chamado". Agente desligado que atendeu trinta clientes tem lição válida.
  it 'não pula a conta cujos agentes estão todos desligados' do
    account = account_with_all_agents_off

    expect { described_class.perform_now }
      .to have_enqueued_job(Ai::Manager::AnalysisJob).with(account.id, 'schedule')
  end
end

require 'rails_helper'

RSpec.describe Ai::Manager::Overview do
  let(:account) { create(:account) }
  let(:overview) { described_class.new(account: account) }

  def scheduled_run!(finished_at)
    create(:ai_manager_run, account: account, triggered_by: 'schedule',
                            status: 'done', finished_at: finished_at)
  end

  describe '#next_run_at' do
    # O defeito que o dono viu na tela: "próxima em 31 de ago." no dia 17 de
    # setembro. A data era a última varredura automática + 7 dias, então uma
    # semana perdida a congelava no passado para sempre — e a tela passava a
    # anunciar com confiança um dia que já tinha ido embora.
    it 'nunca anuncia uma data que já passou' do
      scheduled_run!(3.weeks.ago)

      expect(overview.perform[:next_run_at]).to be > Time.current.to_i
    end

    it 'anuncia a próxima segunda do cron mesmo sem nunca ter rodado sozinho' do
      expect(Time.zone.at(overview.perform[:next_run_at]).wday).to eq(1)
    end
  end

  describe '#schedule_overdue?' do
    # Uma data futura correta esconderia o que importa: o agendador está morto.
    it 'denuncia o agendador parado há mais de uma cadência' do
      scheduled_run!(3.weeks.ago)

      expect(overview.perform[:schedule_overdue]).to be(true)
    end

    it 'fica quieto quando a varredura automática rodou esta semana' do
      scheduled_run!(1.day.ago)

      expect(overview.perform[:schedule_overdue]).to be(false)
    end

    # "Rodar agora" não é o agendador: uma conta onde só houve clique manual
    # continua sem varredura automática, e a tela precisa dizer isso.
    it 'não se cala por causa de uma rodada manual recente' do
      create(:ai_manager_run, account: account, triggered_by: 'manual',
                              status: 'done', finished_at: 1.hour.ago)

      expect(overview.perform[:schedule_overdue]).to be(true)
    end
  end
end

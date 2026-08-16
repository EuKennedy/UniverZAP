# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Reports::Period do
  describe 'a preset number of days' do
    # Trinta dias é hoje mais os 29 anteriores. Contados para trás a partir
    # deste instante, atravessam 31 datas locais e a série sai com uma coluna a
    # mais, meio vazia, na ponta esquerda.
    it 'covers exactly the days it says it covers' do
      expect(described_class.from_days(30).align_to(Time.zone).days).to eq(30)
      expect(described_class.from_days(1).align_to(Time.zone).days).to eq(1)
    end

    it 'refuses to scan more than a year' do
      expect(described_class.from_days(4000).align_to(Time.zone).days).to eq(described_class::MAX_DAYS)
    end
  end

  describe 'a range picked on the calendar' do
    it 'reads the pair of epochs the screen sends' do
      period = described_class.from_params(since: 9.days.ago.to_i, until_at: 3.days.ago.to_i)

      expect(period.align_to(Time.zone).days).to eq(7)
    end

    # Uma data digitada errada não pode derrubar o relatório inteiro.
    it 'falls back to the default rather than raising' do
      expect(described_class.from_params(since: 'ontem', until_at: 'hoje').days).to eq(described_class::DEFAULT_DAYS)
      expect(described_class.from_params(since: nil, until_at: nil).days).to eq(described_class::DEFAULT_DAYS)
    end

    # Um intervalo invertido é o operador arrastando o calendário ao contrário,
    # e devolver uma janela negativa faria toda métrica responder zero sem
    # dizer por quê.
    it 'ignores a range that ends before it starts' do
      period = described_class.from_params(since: 2.days.ago.to_i, until_at: 9.days.ago.to_i)

      expect(period.days).to eq(described_class::DEFAULT_DAYS)
    end

    it 'caps a range nobody should be able to ask for' do
      period = described_class.from_params(since: 10.years.ago.to_i, until_at: Time.current.to_i)

      expect(period.align_to(Time.zone).days).to eq(described_class::MAX_DAYS)
    end
  end

  describe 'the window before' do
    # Comparar março com fevereiro seria comparar 31 dias com 28, então o que
    # vale é a duração e não o mês.
    it 'has the same duration and ends where this one starts' do
      period = described_class.from_days(30)

      expect(period.previous.length).to eq(period.length)
      expect(period.previous.ends_at).to eq(period.starts_at)
    end
  end

  describe 'the business clock' do
    # Uma conta em São Paulo com o app em UTC começaria a janela às 21h da
    # véspera, e a primeira coluna do gráfico seria uma noite solta que ninguém
    # pediu.
    it 'starts the window at midnight where the business is' do
      zone = ActiveSupport::TimeZone['America/Sao_Paulo']
      aligned = described_class.from_days(7).align_to(zone)

      expect(aligned.starts_at.in_time_zone(zone).hour).to be_zero
      expect(aligned.days).to eq(7)
    end
  end
end

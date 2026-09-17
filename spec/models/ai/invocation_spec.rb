require 'rails_helper'

RSpec.describe Ai::Invocation do
  # Perguntar como usar o produto é suporte nosso, não uso de IA do cliente:
  # cobrar por isso faria o cliente pensar duas vezes antes de pedir ajuda.
  describe '.billable?' do
    it 'não cobra a conversa com o Guia do wiki' do
      expect(described_class.billable?('wiki_chat')).to be(false)
    end

    it 'cobra tudo o mais, inclusive o copiloto do atendente' do
      expect(described_class.billable?('copilot_chat')).to be(true)
      expect(described_class.billable?('autopilot')).to be(true)
    end

    it 'trata fase nula como cobrável, para nunca deixar de cobrar por engano' do
      expect(described_class.billable?(nil)).to be(true)
    end
  end

  # Fase fora de PHASES falha na validação, e log_success engole a exceção de
  # gravação: a linha de auditoria some em silêncio e o custo aparece como zero.
  it 'reconhece wiki_chat como fase válida' do
    expect(described_class::PHASES).to include('wiki_chat')
  end

  it 'mantém toda fase não cobrável dentro da lista de fases válidas' do
    expect(described_class::PHASES).to include(*described_class::UNBILLED_PHASES)
  end
end

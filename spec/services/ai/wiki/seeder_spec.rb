require 'rails_helper'

RSpec.describe Ai::Wiki::Seeder do
  let(:account) { create(:account) }

  it 'cria o Guia com propósito de wiki' do
    assistant = described_class.for(account)

    expect(assistant.purpose).to eq('wiki')
    expect(assistant.name).to eq(described_class::NAME)
  end

  it 'dá ao Guia uma seção do manual por documento' do
    assistant = described_class.for(account)

    expect(assistant.trainings.count).to eq(Ai::Wiki::Manual.sections.size)
    expect(assistant.trainings.pluck(:status).uniq).to eq(['ready'])
  end

  # Roda no nascimento do Guia e de novo a cada edição do manual. Duplicar aqui
  # significaria o mesmo trecho concorrendo consigo mesmo no ranking.
  it 'não duplica nada quando roda de novo' do
    described_class.for(account)

    expect { described_class.for(account) }
      .to not_change { account.ai_assistants.wiki.count }
      .and(not_change { Ai::Training.where(account: account).count })
  end

  # Seção apagada do manual tem que sumir do agente, senão ele segue ensinando
  # com confiança uma tela que não existe mais.
  it 'remove o documento de uma seção que saiu do manual' do
    assistant = described_class.for(account)
    assistant.trainings.create!(account: account, title: 'Seção aposentada', content: 'texto antigo',
                                source_type: 'text', category: 'base', status: 'ready')

    described_class.for(account)

    expect(assistant.trainings.pluck(:title)).not_to include('Seção aposentada')
  end

  # Ele mora na mesma tabela dos agentes de atendimento, e é isso que o mantém
  # fora da lista que a operação gerencia e do seletor do copiloto.
  it 'fica de fora dos agentes de atendimento' do
    described_class.for(account)

    expect(account.ai_assistants.attendance.pluck(:purpose)).to all(eq('attendance'))
  end
end

require 'rails_helper'

RSpec.describe Whatsapp::Flows::TemplateLibrary do
  let(:account) { create(:account) }

  it 'lista os três modelos do salão quando a conta é desse vertical' do
    account.update!(custom_attributes: { 'vertical_template' => 'beauty_salon' })

    expect(described_class.available(account).map(&:key)).to eq(
      %w[beauty_salon/agendamento beauty_salon/cadastro_cliente beauty_salon/pesquisa_pos_atendimento]
    )
  end

  it 'recusa chave fora do padrão em vez de abrir arquivo arbitrário' do
    expect(described_class.find('../../config/database')).to be_nil
    expect(described_class.find('beauty_salon/agendamento')).to be_present
  end

  describe '#build' do
    let(:template) { described_class.find('beauty_salon/agendamento') }

    def servico_options(json)
      form = json.dig('screens', 0, 'layout', 'children').detect { |c| c['type'] == 'Form' }
      form['children'].detect { |c| c['name'] == 'servico' }['data-source']
    end

    it 'cria os atributos que o mapeamento vai preencher' do
      described_class.new(account: account, template: template).build

      keys = account.custom_attribute_definitions.pluck(:attribute_key)
      expect(keys).to include('servico', 'profissional', 'data_agendamento', 'periodo_agendamento', 'observacao_agendamento')
    end

    # As opções do formulário são as MESMAS do painel: se o salão cadastrou os
    # serviços dele, é isso que o cliente vê.
    it 'usa a lista do atributo da conta como opções do campo' do
      account.custom_attribute_definitions.create!(
        attribute_key: 'servico', attribute_display_name: 'Serviço', attribute_model: 'conversation_attribute',
        attribute_display_type: 'list', attribute_values: %w[Progressiva Luzes]
      )

      json = described_class.new(account: account, template: template).build

      expect(servico_options(json)).to eq([{ 'id' => 'progressiva', 'title' => 'Progressiva' }, { 'id' => 'luzes', 'title' => 'Luzes' }])
    end

    it 'cai na lista do modelo quando a conta não tem o atributo' do
      json = described_class.new(account: account, template: template).build

      expect(servico_options(json).first).to eq('id' => 'corte', 'title' => 'Corte')
      expect(json.to_json).not_to include('$attribute')
    end
  end
end

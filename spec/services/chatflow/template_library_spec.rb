require 'rails_helper'

RSpec.describe Chatflow::TemplateLibrary do
  let(:account) { create(:account, custom_attributes: { 'vertical_template' => 'beauty_salon' }) }

  it 'lista os modelos do vertical da conta' do
    keys = described_class.available(account).map(&:key)

    expect(keys).to contain_exactly('beauty_salon/agendamento', 'beauty_salon/pos_atendimento', 'beauty_salon/recompra')
  end

  it 'conta sem vertical vê todos' do
    account.update!(custom_attributes: {})

    expect(described_class.available(account).size).to eq(5)
  end

  it 'recusa chave fora do padrão' do
    expect(described_class.find('../../etc/passwd')).to be_nil
  end

  Dir[Rails.root.join('lib/chatflow_templates/*/*.yml')].each do |path|
    key = "#{File.basename(File.dirname(path))}/#{File.basename(path, '.yml')}"

    it "instala #{key} desligado, ligado de ponta a ponta" do
      template = described_class.find(key)
      flow = described_class.new(account: account, template: template).install!

      expect(flow).to be_status_draft
      expect(flow.test_mode).to be(false)
      expect(flow.nodes.count).to eq(template.nodes.size)
      expect(flow.edges.count).to eq(template.edges.size)
      expect(flow.start_node).to be_present
      expect(flow.trigger_type).to eq(template.trigger_type)
    end
  end

  it 'cria as etiquetas citadas pelo título' do
    template = described_class.find('ecommerce/carrinho_abandonado')
    flow = described_class.new(account: account, template: template).install!

    label = account.labels.find_by(title: 'carrinho-abandonado')
    expect(flow.trigger_label_ids).to eq([label.id])
  end
end

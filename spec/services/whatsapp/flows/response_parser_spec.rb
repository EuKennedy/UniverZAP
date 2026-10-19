require 'rails_helper'

RSpec.describe Whatsapp::Flows::ResponseParser do
  let(:flow) { create(:whatsapp_flow, :published, name: 'Agendamento') }
  let(:conversation) { create(:conversation, inbox: flow.inbox, account: flow.account) }
  let(:original) { Whatsapp::Flows::SendService.new(flow: flow, conversation: conversation, text: 'Vamos?', cta: 'Agendar').perform }
  let(:token) { Whatsapp::Flows::FlowToken.generate(original.id) }

  def parse(answers)
    described_class.new({ 'name' => 'flow', 'body' => 'Sent', 'response_json' => answers.to_json }).parse
  end

  it 'monta o texto com os rótulos e os títulos das opções, não com ids' do
    parsed = parse(flow_token: token, servico: 'coloracao', observacao: 'sem amônia')

    expect(parsed.content).to eq("Agendamento\nServiço: Coloração\nObservações: sem amônia")
    expect(parsed.flow_response[:flow_id]).to eq(flow.id)
    expect(parsed.flow_response[:original_message_id]).to eq(original.id)
    expect(parsed.flow_response[:fields].first).to include(name: 'servico', value: 'Coloração', raw: 'coloracao')
  end

  it 'omite campos vazios do texto e traduz booleanos' do
    parsed = parse(flow_token: token, servico: 'corte', observacao: '', aceita: true)

    expect(parsed.content).to eq("Agendamento\nServiço: Corte\naceita: Sim")
  end

  # Token forjado ou de outra instalação não leva a nenhum Flow: a resposta
  # ainda vira mensagem legível, mas sem mapeamento.
  it 'não confia num token que não assinamos' do
    parsed = parse(flow_token: 'abc--def', servico: 'corte')

    expect(parsed.flow_response[:flow_id]).to be_nil
    expect(parsed.content).to eq('servico: corte')
  end

  it 'sobrevive a um response_json que não é JSON' do
    parsed = described_class.new({ 'body' => 'Sent', 'response_json' => '{nope' }).parse

    expect(parsed.content).to eq('Sent')
    expect(parsed.flow_response[:fields]).to eq([])
  end
end

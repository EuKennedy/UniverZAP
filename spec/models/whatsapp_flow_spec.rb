require 'rails_helper'

RSpec.describe WhatsappFlow do
  let(:flow) { create(:whatsapp_flow) }

  it 'lê os rótulos dos campos de entrada do próprio Flow JSON, sem o contêiner Form' do
    expect(flow.field_labels).to eq('servico' => 'Serviço', 'observacao' => 'Observações')
  end

  it 'lê os títulos das opções por campo' do
    expect(flow.field_options).to eq('servico' => { 'corte' => 'Corte', 'coloracao' => 'Coloração' })
  end

  it 'exige pelo menos uma tela' do
    flow.flow_json = { 'version' => '7.3', 'screens' => [] }

    expect(flow).not_to be_valid
  end

  # A Meta não aceita edição de Flow publicado; divergir do que ela tem é
  # mandar um formulário diferente do que o operador vê.
  it 'congela o JSON depois de publicado' do
    published = create(:whatsapp_flow, :published)
    published.flow_json = published.flow_json.merge('version' => '7.2')

    expect(published).not_to be_valid
    expect(published.errors[:flow_json].first).to include('duplicate')
  end

  it 'manda rascunho em modo draft e publicado em modo published' do
    expect(flow.send_mode).to eq('draft')
    expect(create(:whatsapp_flow, :published).send_mode).to eq('published')
  end
end

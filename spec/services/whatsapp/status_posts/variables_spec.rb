require 'rails_helper'

RSpec.describe Whatsapp::StatusPosts::Variables do
  let(:account) { create(:account, name: 'Bela Já') }

  it 'fills each variable for the connection and the day it goes out' do
    at = Time.zone.local(2026, 10, 20, 9) # terça
    text = 'Oi da {{conexao}} ({{ empresa }}): {{dia_semana}}, {{data}}'

    expect(described_class.render(text, account: account, inbox_name: 'Loja Centro', at: at))
      .to eq('Oi da Loja Centro (Bela Já): terça-feira, 20/10')
  end

  # Erro de digitação tem que aparecer, e não sumir do status.
  it 'keeps unknown variables as they were written' do
    expect(described_class.render('{{cupom}}', account: account, inbox_name: 'X')).to eq('{{cupom}}')
  end
end

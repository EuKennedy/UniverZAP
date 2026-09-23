require 'rails_helper'

RSpec.describe Chatflow::ConfirmationMatcher do
  let(:account) { create(:account) }
  let(:chatflow) { Chatflow.create!(account: account, name: 'SAC') }
  let(:node) do
    ChatflowNode.create!(
      chatflow: chatflow, account: account, kind: :confirmation,
      config: {
        'text' => 'Seu problema foi resolvido?',
        'resolved_keywords' => %w[sim resolveu obrigado],
        'unresolved_keywords' => ['não', 'nao resolveu', 'quero humano']
      }
    )
  end

  def match(reply)
    described_class.new(node, reply).match
  end

  it 'casa o ramo positivo' do
    expect(match('sim')).to eq(ChatflowNode::RESOLVED)
    expect(match('obrigado!')).to eq(ChatflowNode::RESOLVED)
  end

  it 'casa o ramo negativo' do
    expect(match('quero humano')).to eq(ChatflowNode::UNRESOLVED)
  end

  # "não resolveu" CONTÉM "resolveu". Testando o positivo primeiro, toda recusa
  # que use a palavra do problema viraria um sim — e o cliente que pediu ajuda
  # receberia o encerramento.
  it 'lê "não resolveu" como recusa, e não como confirmação' do
    expect(match('não resolveu')).to eq(ChatflowNode::UNRESOLVED)
    expect(match('nao, nao resolveu meu problema')).to eq(ChatflowNode::UNRESOLVED)
  end

  # Quem responde no WhatsApp escreve "nao", "Não!" e "NÃO." esperando que as
  # três funcionem.
  it 'ignora acento, maiúscula e pontuação' do
    expect(match('NÃO.')).to eq(ChatflowNode::UNRESOLVED)
    expect(match('nao')).to eq(ChatflowNode::UNRESOLVED)
    expect(match('Sim!!!')).to eq(ChatflowNode::RESOLVED)
  end

  it 'não casa nada quando a resposta não tem nenhuma palavra-chave' do
    expect(match('mais ou menos')).to be_nil
    expect(match('')).to be_nil
    expect(match(nil)).to be_nil
  end

  it 'casa a palavra-chave no meio de uma frase' do
    expect(match('ah sim, era isso mesmo')).to eq(ChatflowNode::RESOLVED)
  end
end

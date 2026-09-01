# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Manager::Conversations::Reader do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:now) { Time.zone.parse('2026-08-31 18:00:00') }
  let(:claude) { instance_double(Ai::ClaudeService) }

  let(:said) { 'Queria fazer o Blond, ainda dá pra sábado?' }

  before do
    allow(assistant).to receive(:resolved_anthropic_key).and_return('sk-test')
    allow(Ai::ClaudeService).to receive(:new).and_return(claude)
  end

  def talk(text: nil, name: 'Fernanda')
    contact = create(:contact, account: account, name: name)
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
    create(:message, account: account, inbox: inbox, conversation: conversation,
                     message_type: :incoming, content: text || said, created_at: now - 8.hours)
    conversation
  end

  def answers(json)
    allow(claude).to receive(:chat).and_return({ content: json, invocation: nil })
  end

  def reply(key: 'compra_travada', reason: 'A cliente queria o Blond e a conversa parou.', quote: nil)
    { casos: [{ chave: key, motivo: reason, trecho: quote || said }] }.to_json
  end

  def read(limit: described_class::MAX_READ)
    triage = Ai::Manager::Conversations::Triage.new(account: account, since: now - 30.days, now: now)
    described_class.new(account: account, assistant: assistant, details: triage.details,
                        candidates: triage.candidates, waits: triage.waits, limit: limit, now: now)
  end

  describe 'o que vira cartão' do
    before { talk }

    it 'transforma o caso devolvido pelo modelo num achado etiquetado como leitura' do
      answers(reply)

      finding = read.findings.first

      expect(finding[:case_key]).to eq('compra_travada')
      expect(finding[:source]).to eq('reading')
      expect(finding[:detail]).to include('Blond')
    end

    it 'usa o título do catálogo e não o texto que o modelo inventar' do
      answers(reply)

      expect(read.findings.first[:title]).to eq('Cliente quis comprar e a conversa parou')
    end

    # O JSON quase nunca vem limpo: o modelo gosta de embrulhar em cerca de
    # código ou escrever uma frase antes. Recortar o objeto é o que impede um
    # cartão de sumir por causa de três crases.
    it 'acha o JSON mesmo embrulhado em texto' do
      answers("Claro! Segue:\n```json\n#{reply}\n```")

      expect(read.findings.length).to eq(1)
    end
  end

  describe 'o que é descartado' do
    before { talk }

    # A tela não sabe rotular uma categoria inventada, e o operador leria um
    # cartão sem nome.
    it 'ignora chave fora do catálogo' do
      answers(reply(key: 'cliente_simpatico'))

      expect(read.findings).to be_empty
    end

    it 'ignora caso sem motivo, porque um cartão sem frase não diz nada a ninguém' do
      answers(reply(reason: '   '))

      expect(read.findings).to be_empty
    end

    it 'não quebra a rodada quando o modelo devolve algo que não é JSON' do
      answers('desculpa, não entendi')

      expect(read.findings).to be_empty
    end

    it 'segue em frente quando a leitura de uma conversa estoura' do
      allow(claude).to receive(:chat).and_raise(Ai::ClaudeService::Error, 'quota estourada')

      expect(read.findings).to be_empty
    end

    it 'guarda no máximo dois casos por conversa, os que couberem' do
      answers({ casos: [
        { chave: 'compra_travada', motivo: 'um', trecho: said },
        { chave: 'pedido_de_humano', motivo: 'dois', trecho: said },
        { chave: 'cliente_insatisfeito', motivo: 'três', trecho: said }
      ] }.to_json)

      expect(read.findings.length).to eq(2)
    end
  end

  describe 'a citação' do
    before { talk }

    # A regra que segura a feature de pé: o cartão nunca mostra frase que o
    # cliente não escreveu. Quando o modelo parafraseia, a saída não é confiar
    # nele, é trocar pelo texto real e registrar que a citação não conferiu.
    it 'aceita a cópia literal e marca como conferida' do
      answers(reply(quote: said))

      finding = read.findings.first

      expect(finding[:excerpt]).to eq(said)
      expect(finding[:metadata]['excerpt_verified']).to be(true)
    end

    it 'troca a citação inventada pelo que a cliente escreveu de verdade' do
      answers(reply(quote: 'Ela disse que queria o serviço de loiro no fim de semana'))

      finding = read.findings.first

      expect(finding[:excerpt]).to eq(said)
      expect(finding[:metadata]['excerpt_verified']).to be(false)
    end
  end

  describe 'o teto de leitura' do
    # O que ficou de fora tem que ser contável, porque é ele que diz se dá para
    # confiar no vazio do resto.
    it 'lê no máximo o teto e continua sabendo quantas eram' do
      talk(name: 'Ana')
      talk(name: 'Bia')
      answers(reply)

      reader = read(limit: 1)
      reader.findings

      expect(reader.read_count).to eq(1)
      expect(reader.candidate_count).to eq(2)
    end
  end

  describe 'sem chave de API' do
    before do
      talk
      allow(assistant).to receive(:resolved_anthropic_key).and_return(nil)
    end

    # Não é erro: a aba continua útil só com a triagem, que é de graça. O motivo
    # sobe para a tela em vez de a rodada terminar com uma lista curta e muda.
    it 'não lê nada e diz por quê, em vez de falhar' do
      reader = read

      expect(reader.findings).to be_empty
      expect(reader.skipped_reason).to include('sem chave')
    end

    it 'nunca chama o modelo' do
      read.findings

      expect(Ai::ClaudeService).not_to have_received(:new)
    end
  end
end

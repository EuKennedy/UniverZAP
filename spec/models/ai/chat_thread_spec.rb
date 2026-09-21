require 'rails_helper'

RSpec.describe Ai::ChatThread do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:assistant) { create(:ai_assistant, account: account) }
  let(:thread) do
    described_class.create!(account: account, user: user, ai_assistant: assistant, title: 'Ajuda')
  end

  def say(role, content, at)
    thread.chat_messages.create!(role: role, content: content, created_at: at)
  end

  describe '#recent_messages_for_llm' do
    # O bug que fazia o Guia repetir a resposta: a associação já carrega
    # `order(created_at: :asc)`, um `.order(:desc)` encadeado só ACRESCENTA, e a
    # ascendente continuava decidindo. O LIMIT trazia as mais ANTIGAS e o
    # `.reverse` entregava a thread de trás para frente — a última entrada, que é
    # a que o modelo responde, virava a pergunta mais velha da conversa.
    it 'entrega a conversa na ordem em que aconteceu' do
      say('user', 'primeira', 3.hours.ago)
      say('assistant', 'resposta da primeira', 2.hours.ago)
      say('user', 'segunda', 1.hour.ago)

      expect(thread.recent_messages_for_llm.map(&:content))
        .to eq(['primeira', 'resposta da primeira', 'segunda'])
    end

    it 'termina na pergunta que a pessoa acabou de fazer' do
      say('user', 'primeira', 2.hours.ago)
      say('assistant', 'resposta', 1.hour.ago)
      say('user', 'a nova', 1.minute.ago)

      expect(thread.recent_messages_for_llm.last.content).to eq('a nova')
    end

    # Passando da janela, o que se perde é o começo — nunca o fim.
    it 'descarta o mais velho quando a conversa passa da janela' do
      (described_class::RECENT_MESSAGE_WINDOW + 3).times do |index|
        say('user', "mensagem #{index}", (100 - index).minutes.ago)
      end

      window = thread.recent_messages_for_llm

      expect(window.size).to eq(described_class::RECENT_MESSAGE_WINDOW)
      expect(window.last.content).to eq("mensagem #{described_class::RECENT_MESSAGE_WINDOW + 2}")
      expect(window.first.content).to eq('mensagem 3')
    end
  end
end

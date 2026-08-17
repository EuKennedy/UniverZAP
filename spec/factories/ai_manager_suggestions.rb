FactoryBot.define do
  factory :ai_manager_suggestion, class: 'Ai::Manager::Suggestion' do
    ai_assistant
    account { ai_assistant.account }
    ai_manager_run { association :ai_manager_run, account: ai_assistant.account }
    check_key { 'loose_promise' }
    severity { 'high' }
    # A bandeira `promessa_solta` dispara quando a resposta AFIRMA que agendou e
    # nenhuma escrita saiu no turno, não quando o agente promete voltar depois.
    # A fixture já descreveu a falha errada, e um teste com a história errada
    # dentro passa por acidente e ensina a próxima pessoa a coisa errada.
    title { 'O agente afirma que agendou sem ter agendado' }
    rationale { '4 de 40 respostas do período confirmaram um horário que não entrou na agenda.' }
    evidence do
      {
        'conversation_id' => 77, 'excerpt' => 'Prontinho, marquei sua escova pra quinta às 14h.',
        'metric' => 'porcentagem_das_respostas', 'value' => 10.0
      }
    end
    target { 'prompt_version' }
    proposed do
      { 'instruction' => 'Só diga que agendou depois que a ferramenta confirmar. Sem confirmação, ' \
                         'consulte agora e responda na mesma mensagem.' }
    end
    status { 'pending' }

    # A outra alavanca: memória em vez de instrução.
    trait :training do
      check_key { 'died_on_price' }
      target { 'training' }
      proposed do
        { 'title' => 'Como responder pergunta de preço', 'category' => 'sales',
          'content' => 'Responda o valor exato que está escrito nesta base.' }
      end
    end
  end
end

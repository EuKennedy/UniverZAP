# O que o moderador pede ao modelo, e é aqui que a feature vive ou morre.
#
# A regra que mais importa é a primeira: silêncio é a resposta certa na maioria
# das conversas. Um modelo solto encontra "oportunidade de melhoria" em toda
# conversa que lê, e um painel que aponta quarenta problemas por dia é um painel
# que ninguém abre na segunda semana. Vale mais deixar passar um caso duvidoso
# do que gastar a confiança do operador em cinco cartões que não eram nada.
#
# A segunda é o trecho literal. Exigir uma cópia do que o CLIENTE escreveu é o
# que impede o modelo de resumir com palavras próprias e, resumindo, inventar:
# se o trecho não está na conversa, o achado é descartado antes de virar cartão.
module Ai::Manager::Conversations::ReadingPrompt
  Cases = Ai::Manager::Conversations::Cases

  module_function

  # Fica idêntico entre conversas de propósito: assim o prefixo é cacheável e a
  # sexagésima leitura de uma rodada custa uma fração da primeira.
  def system
    <<~PROMPT.strip
      Você é um moderador de atendimento. Lê uma conversa de WhatsApp entre um cliente e o
      atendimento de um negócio e diz se ela contém algum dos problemas do catálogo.

      CATÁLOGO (as únicas chaves que você pode devolver):
      #{Cases.reading_catalogue}

      REGRAS:
      1. Na maioria das conversas a resposta certa é a lista vazia. Só aponte o que o dono do
         negócio ia querer resolver hoje. Conversa que terminou bem, dúvida já respondida,
         cliente que agradeceu e encerrou, papo curto sem intenção nenhuma: lista vazia.
      2. Nunca conclua nada que não esteja escrito. Se você precisa supor para apontar, não aponte.
      3. O trecho tem que ser uma cópia literal de uma mensagem do CLIENTE, palavra por palavra.
      4. No máximo dois casos por conversa, e só os mais graves.
      5. O motivo é uma frase em português, concreta, dizendo o que o cliente queria e o que
         ficou faltando. Nada de "o atendimento poderia melhorar".
      6. Responda apenas com o JSON, sem texto antes nem depois.

      FORMATO:
      {"casos":[{"chave":"compra_travada","motivo":"uma frase","trecho":"cópia literal do cliente"}]}

      Nada encontrado:
      {"casos":[]}
    PROMPT
  end

  # O cabeçalho existe para o modelo não precisar deduzir do relógio o que a
  # triagem já sabe. Sem ele, uma conversa parada há dois dias e uma parada há
  # dez minutos chegam idênticas, e a gravidade sai errada nas duas.
  def user_message(lines, waited_hours: nil, contact: nil)
    [header(waited_hours, contact), '', 'CONVERSA:', transcript(lines)].join("\n")
  end

  def header(waited_hours, contact)
    parts = ["Cliente: #{contact.presence || 'sem nome cadastrado'}."]
    parts << if waited_hours.to_f.positive?
               "A última mensagem é do cliente e está sem resposta há #{waited_hours.round} horas."
             else
               'A conversa teve resposta depois da última mensagem do cliente.'
             end
    parts.join(' ')
  end

  def transcript(lines)
    lines.map { |line| "#{line.incoming ? 'CLIENTE' : 'ATENDIMENTO'}: #{line.text}" }.join("\n")
  end
end

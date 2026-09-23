# Para qual saída da Confirmação a resposta do cliente vai.
#
# Diferente do menu, aqui não existe número para digitar nem rótulo para casar:
# o cliente responde do jeito que fala. Por isso cada ramo carrega uma LISTA de
# palavras-chave, e o casamento é por conteúdo — "não, não resolveu" precisa
# cair em não-resolvido mesmo sem ser igual a nada.
#
# ## A ordem importa, e é "não resolvido" primeiro
#
# "não resolveu" contém "resolveu". Testando o ramo positivo antes, toda recusa
# que use a palavra do problema viraria um "sim" — e o cliente que pediu ajuda
# receberia o encerramento. Errar para o lado de mandar para um humano é o erro
# barato; o contrário fecha um chamado aberto.
class Chatflow::ConfirmationMatcher
  def initialize(node, reply_text)
    @node = node
    @text = normalize(reply_text)
  end

  # Devolve 'resolved', 'unresolved' ou nil quando nada casou.
  def match
    return nil if @text.blank?

    return ChatflowNode::UNRESOLVED if hit?(ChatflowNode::UNRESOLVED)
    return ChatflowNode::RESOLVED if hit?(ChatflowNode::RESOLVED)

    nil
  end

  private

  def hit?(handle)
    @node.confirmation_keywords(handle).any? { |word| @text.include?(normalize(word)) }
  end

  # Acento fora e pontuação fora: quem responde no WhatsApp escreve "nao",
  # "Não!", "NÃO." e espera que as três funcionem. Sem isto, a palavra-chave
  # cadastrada com acento nunca casaria com a resposta digitada sem.
  def normalize(text)
    text.to_s.downcase.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').gsub(/[[:punct:]]/, ' ').squeeze(' ').strip
  end
end

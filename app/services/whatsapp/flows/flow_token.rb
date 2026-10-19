# O `flow_token` que vai no envio e volta na resposta.
#
# A resposta de um Flow NÃO traz o id do Flow nem referência confiável além
# deste token (o `context.id` existe, mas a Meta documenta o token como o
# identificador do negócio). Assinar o id da mensagem resolve as duas coisas:
# achamos a mensagem original sem consultar nada por fora e um token forjado
# não passa.
module Whatsapp::Flows::FlowToken
  PURPOSE = 'whatsapp_flow'.freeze

  def self.generate(message_id)
    verifier.generate(message_id.to_i)
  end

  def self.message_for(token)
    message_id = verifier.verified(token.to_s)
    Message.find_by(id: message_id) if message_id
  end

  def self.verifier
    Rails.application.message_verifier(PURPOSE)
  end
end

# What the model should DO when the salon refuses, per error code — never what
# the salon SAID.
#
# Their validation messages are an English array written for us, and their
# business ones are technical: "Profissional indisponível" means the professional
# is hidden from the public, which is nothing a customer can act on. Every line
# here names the next move, because left as a bare fact the model fills the gap
# with "volto já já" — a follow-up it has no turn to perform.
class Ai::Belezaki::ErrorAdvice
  BY_CODE = {
    'slot_taken' => 'Esse horário acabou de ser preenchido. Consulte os horários de novo e ofereça outras opções.',
    'validation_failed' => 'Não consegui montar esse pedido. Consulte os horários de novo e ofereça outro, ' \
                           'sem mencionar erro técnico.',
    'http_400' => 'O salão recusou esse dado. Tente outro profissional ou outro horário e não repasse isso ao cliente.',
    'http_429' => 'A agenda não respondeu agora. Diga que a equipe confirma o horário, não ofereça horário ' \
                  'e não prometa voltar depois.',
    # The salon's own rule, phrased so the agent hands over instead of arguing
    # about it with the customer.
    'notice_window_closed' => 'Está perto demais do horário para mexer sozinho. Explique isso e diga que a ' \
                              'equipe vai confirmar.',
    'not_cancellable' => 'Esse agendamento não pode mais ser cancelado. Explique e diga que a equipe confirma.',
    'not_reschedulable' => 'Esse agendamento não pode mais ser remarcado. Explique e diga que a equipe confirma.',
    'not_billable' => 'Esse agendamento não está mais ativo, então não dá para abrir a comanda. Confirme com o ' \
                      'cliente qual agendamento ele quer.',
    # Codes the salon started returning once its refusals became machine-readable.
    # Each names a fix the agent can carry out in the same conversation, which is
    # the whole point: before these existed it could only improvise an excuse.
    'professional_unavailable' => 'Esse profissional não está disponível. Ofereça outro que faça o mesmo serviço.',
    'professional_does_not_offer' => 'Esse profissional não faz esse serviço. Consulte quem faz e ofereça essa pessoa.',
    'service_unavailable' => 'Esse serviço não está disponível para agendamento. Ofereça outro do catálogo.'
  }.freeze

  # 401, 404, 503, 500 and network failures land here: the agenda is not
  # reachable, and the only honest answer is to stop offering times.
  UNREACHABLE = <<~ADVICE.squish.freeze
    Não consegui falar com a agenda do salão. Diga que a equipe confirma o horário,
    não ofereça horário e não prometa voltar depois.
  ADVICE

  def self.for(code)
    BY_CODE.fetch(code, UNREACHABLE)
  end
end

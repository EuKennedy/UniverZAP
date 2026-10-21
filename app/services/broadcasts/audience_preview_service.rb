# "Quem vai receber?" antes de confirmar o disparo. Só lê, nunca grava.
#
# Devolve o total do público, quantos ficam de fora pela guarda (opt-out, em
# atendimento agora), uma amostra com o texto EXATO que cada um receberia
# (versão sorteada + spintax + variáveis), quem tem variável vazia e uma
# estimativa de quanto tempo a cadência leva para chegar em todos.
# `unconsented_count` é quem nunca falou com o salão (veio de grupo/CSV frio):
# fora do público até o disparo ter a confirmação gravada.
class Broadcasts::AudiencePreviewService
  SAMPLE_SIZE = 20

  def initialize(broadcast)
    @broadcast = broadcast
    @account = broadcast.account
  end

  def perform
    resolver = Broadcasts::AudienceResolver.new(@broadcast)
    ids = resolver.contact_ids
    cold = resolver.missing_phone_numbers.length
    already = @broadcast.broadcast_recipients.pluck(:contact_id)
    fresh = ids - already
    blocked = Broadcasts::RecipientGuard.blocked_ids(@account, fresh, quiet_hours: @broadcast.quiet_hours)
    eligible = fresh.length + cold - blocked.values.sum(&:length)

    {
      count: ids.length + cold, new_count: fresh.length + cold, eligible_count: eligible,
      excluded: blocked.transform_values(&:length),
      unconsented_count: resolver.unconsented_contact_ids.length,
      cold_contacts_confirmed: @broadcast.cold_contacts_confirmed?,
      sample: sample(fresh, blocked),
      estimate: estimate(eligible)
    }
  end

  private

  def sample(ids, blocked)
    contacts = @account.contacts.where(id: ids).order(:id).limit(SAMPLE_SIZE).to_a
    best = Broadcasts::BestTimeService.new(@account, window: @broadcast.send_window).best_hours(contacts.map(&:id))
    contacts.map { |contact| sample_row(contact, blocked, best[contact.id]) }
  end

  def sample_row(contact, blocked, best_hour)
    conversation = contact.conversations.where(inbox_id: @broadcast.inbox_id).order(:id).last
    renderer = Broadcasts::MessageRenderer.new(contact: contact, conversation: conversation, seed: contact.id)
    part = first_part
    {
      contact_id: contact.id, name: contact.name, phone: contact.phone_number,
      text: renderer.render(part['text'].presence || part['caption'], variants: part['variants']),
      missing_variables: renderer.missing_variables(part['text'], part['caption'], part['variants']),
      skip_reason: blocked.find { |_, list| list.include?(contact.id) }&.first,
      best_hour: best_hour
    }
  end

  def first_part
    message = @broadcast.message || {}
    list = message['messages']
    (list.is_a?(Array) && list.first) || message
  end

  # Ritmo real: o menor entre o teto por hora e o que o intervalo médio deixa
  # sair; por dia, o menor entre o teto diário e as horas da janela.
  def estimate(count)
    window = @broadcast.send_window
    average_delay = (@broadcast.delay_min + @broadcast.delay_max) / 2.0
    per_hour = [@broadcast.hourly_cap, (3600 / average_delay).floor].min.clamp(1, nil)
    per_day = [@broadcast.daily_cap, per_hour * (window.end_hour - window.start_hour)].min
    { per_hour: per_hour, per_day: per_day, days: count.positive? ? (count.to_f / per_day).ceil : 0,
      window_start: window.start_hour, window_end: window.end_hour, weekdays: window.weekdays }
  end
end

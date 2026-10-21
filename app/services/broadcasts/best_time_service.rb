# "Quando essa cliente costuma responder?" — a hora do dia (no fuso do salão)
# em que ela mais mandou mensagem nos últimos meses. Mensagem que chega na hora
# em que a pessoa está com o celular na mão é respondida, não ignorada; e
# resposta é o melhor sinal de reputação que um número não oficial pode ter.
#
# Com menos de MIN_SAMPLES mensagens não há padrão: devolve nil e quem chamou
# usa o horário normal.
class Broadcasts::BestTimeService
  LOOKBACK = 180.days
  MIN_SAMPLES = 3

  def initialize(account, window: nil)
    @account = account
    @window = window || Broadcasts::SendWindow.default_for(account)
  end

  # { contact_id => hora (0..23) } só para quem tem padrão.
  def best_hours(contact_ids)
    ids = Array(contact_ids).compact.uniq
    return {} if ids.empty?

    rows = histogram(ids)
    rows.group_by(&:first).each_with_object({}) do |(contact_id, hours), acc|
      next if hours.sum(&:last) < MIN_SAMPLES

      acc[contact_id] = hours.max_by { |(_, hour, count)| [count, -hour] }[1]
    end
  end

  # Para a tela de agendar: a hora e o próximo horário dentro da janela.
  def suggestion(contact, after: Time.current)
    hour = best_hours([contact.id])[contact.id]
    return { hour: nil, at: nil } if hour.nil?

    { hour: hour, at: @window.next_at_hour(hour, after: after) }
  end

  private

  def histogram(ids)
    tz = @window.zone.tzinfo.name
    hour_sql = Arel.sql(ActiveRecord::Base.sanitize_sql_array(
                          ["EXTRACT(HOUR FROM messages.created_at AT TIME ZONE 'UTC' AT TIME ZONE ?)::int", tz]
                        ))
    Message.unscope(:order).joins(:conversation)
           .where(account_id: @account.id, message_type: :incoming, private: false)
           .where(conversations: { contact_id: ids })
           .where(created_at: LOOKBACK.ago..)
           .group('conversations.contact_id', hour_sql)
           .pluck('conversations.contact_id', hour_sql, Arel.sql('COUNT(*)'))
  end
end

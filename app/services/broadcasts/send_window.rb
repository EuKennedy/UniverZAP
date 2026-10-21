# Horário comercial do salão em que um envio automático pode sair.
#
# O fuso é o de relatórios da conta (`reporting_timezone`), caindo em
# America/Sao_Paulo: mensagem de salão às 7h da manhã ou num domingo é o tipo
# de coisa que a cliente denuncia, e denúncia é o que derruba número não oficial.
class Broadcasts::SendWindow
  DEFAULT_TIMEZONE = 'America/Sao_Paulo'.freeze

  attr_reader :start_hour, :end_hour, :weekdays, :zone

  def self.default_for(account)
    defaults = Broadcast::THROTTLE_DEFAULTS
    new(account: account, start_hour: defaults['window_start'], end_hour: defaults['window_end'], weekdays: Broadcast::DEFAULT_WEEKDAYS)
  end

  def initialize(account:, start_hour:, end_hour:, weekdays:)
    @zone = ActiveSupport::TimeZone[account.reporting_timezone.presence || DEFAULT_TIMEZONE] || ActiveSupport::TimeZone[DEFAULT_TIMEZONE]
    @start_hour = start_hour.to_i
    @end_hour = [end_hour.to_i, @start_hour + 1].max
    @weekdays = weekdays
  end

  def open?(time = Time.current)
    local = time.in_time_zone(@zone)
    @weekdays.include?(local.wday) && local.hour >= @start_hour && local.hour < @end_hour
  end

  # O próximo instante em que a janela está aberta (o próprio `time` se já está).
  def next_open(time = Time.current)
    return time if open?(time)

    local = time.in_time_zone(@zone)
    candidate = local.hour < @start_hour ? local.change(hour: @start_hour) : local.tomorrow.change(hour: @start_hour)
    candidate += 1.day until @weekdays.include?(candidate.wday)
    candidate
  end

  # Um horário preferido (ex.: 14h, quando a cliente costuma responder) encaixado
  # na janela, no primeiro dia útil a partir de `after`.
  def next_at_hour(hour, after: Time.current)
    hour = hour.to_i.clamp(@start_hour, @end_hour - 1)
    local = after.in_time_zone(@zone)
    candidate = local.change(hour: hour)
    candidate += 1.day if candidate <= local
    candidate += 1.day until @weekdays.include?(candidate.wday)
    candidate
  end
end

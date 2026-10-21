# Gatilho por data: aniversário, X dias depois do agendamento, de um estágio
# (etiqueta) ou do atendimento encerrado.
#
# Varre de hora em hora (o ScheduledMessages::DueScannerJob chama `perform` a
# cada minuto e a trava do Redis deixa passar uma vez por hora) e só dentro da
# janela de envio da conta (9h–19h, seg–sáb): é o mesmo cuidado anti-bloqueio
# dos disparos. Cada fluxo começa no máximo MAX_PER_RUN conversas por hora, e
# cada conversa no máximo uma vez por data (context['trigger_key']).
class Chatflow::DateTriggerScanner
  MAX_PER_RUN = 30
  LOCK_TTL = 2.hours

  def perform(now: Time.current)
    return unless Redis::Alfred.set(lock_key(now), 1, nx: true, ex: LOCK_TTL.to_i)

    Chatflow.where('status = ? OR test_mode = ?', Chatflow.statuses[:active], true).trigger_date.includes(:account).find_each do |flow|
      scan(flow, now)
    end
  end

  def scan(flow, now)
    config = flow.date_config
    window = Broadcasts::SendWindow.default_for(flow.account)
    local = now.in_time_zone(window.zone)
    return unless window.open?(now) && local.hour >= config['hour']

    started = 0
    conversations_for(flow, config, local.to_date).each do |conversation|
      break if started >= MAX_PER_RUN

      key = "#{config['kind']}:#{local.to_date.iso8601}"
      next if flow.executions.where(conversation_id: conversation.id).exists?(['context ->> ? = ?', 'trigger_key', key])

      execution = Chatflow::EngineService.new(nil, conversation: conversation)
                                         .start_from_event(flow, context: { 'trigger' => 'date', 'trigger_key' => key })
      started += 1 if execution
    end
  end

  private

  def lock_key(now)
    "chatflow:date_scan:#{now.utc.strftime('%Y%m%d%H')}"
  end

  def conversations_for(flow, config, today)
    case config['kind']
    when 'birthday' then birthday_conversations(flow, config['attribute_key'], today)
    when 'after_appointment' then appointment_conversations(flow, today - config['days'])
    when 'after_stage' then stage_conversations(flow, config['label_id'], today - config['days'])
    when 'after_resolution' then resolution_conversations(flow, today - config['days'])
    else []
    end
  end

  def conversations(flow)
    scope = flow.account.conversations
    flow.inbox_id ? scope.where(inbox_id: flow.inbox_id) : scope
  end

  # A data de aniversário vem como a pessoa digitou: ISO (resposta de uma
  # Pergunta) ou dd/mm/aaaa. Contato sem conversa fica de fora.
  def birthday_conversations(flow, key, today)
    contacts = flow.account.contacts.where("custom_attributes ->> ? <> ''", key).select(:id, :custom_attributes)
    contact_ids = contacts.select { |contact| same_day?(contact.custom_attributes[key], today) }.map(&:id)
    latest_per_contact(conversations(flow).where(contact_id: contact_ids))
  end

  def same_day?(raw, today)
    value = raw.to_s
    match = value.match(/\A\d{4}-(\d{2})-(\d{2})/) || value.match(%r{\A(\d{1,2})/(\d{1,2})})
    return false unless match

    month, day = value.include?('/') ? [match[2], match[1]] : [match[1], match[2]]
    month.to_i == today.month && day.to_i == today.day
  end

  def appointment_conversations(flow, date)
    conversations(flow).where("custom_attributes ->> 'data_agendamento' <> ''").select do |conversation|
      Time.zone.parse(conversation.custom_attributes['data_agendamento'].to_s)&.in_time_zone(zone(flow))&.to_date == date
    rescue ArgumentError
      false
    end
  end

  # Quando a etiqueta do estágio entrou na conversa: a data do tagging.
  def stage_conversations(flow, label_id, date)
    title = flow.account.labels.find_by(id: label_id)&.title
    return [] if title.blank?

    range = day_range(flow, date)
    ids = ActsAsTaggableOn::Tagging.joins(:tag).where(taggable_type: 'Conversation', context: 'labels', tags: { name: title })
                                   .where(created_at: range).pluck(:taggable_id)
    conversations(flow).where(id: ids).to_a
  end

  def resolution_conversations(flow, date)
    ids = ReportingEvent.where(account_id: flow.account_id, name: 'conversation_resolved', created_at: day_range(flow, date))
                        .pluck(:conversation_id)
    conversations(flow).where(id: ids).to_a
  end

  def latest_per_contact(scope)
    scope.order(last_activity_at: :desc).to_a.uniq(&:contact_id)
  end

  def day_range(flow, date)
    tz = zone(flow)
    tz.local(date.year, date.month, date.day).all_day
  end

  def zone(flow)
    Broadcasts::SendWindow.default_for(flow.account).zone
  end
end

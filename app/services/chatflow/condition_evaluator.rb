# O "se/senão" do Chatflow. Avalia as regras da etapa Condição contra a
# conversa naquele instante e diz por qual saída seguir (`true`/`false`).
#
# config:
#   { 'match' => 'all' | 'any',
#     'rules' => [
#       { 'type' => 'label', 'operator' => 'has'|'not_has', 'label_ids' => [1, 2] },
#       { 'type' => 'attribute', 'scope' => 'contact'|'conversation', 'key' => 'servico',
#         'operator' => 'equals'|'not_equals'|'contains'|'present'|'blank'|'greater'|'less', 'value' => 'corte' },
#       { 'type' => 'lead_source', 'value' => 'anuncio_facebook'|'organico' },
#       { 'type' => 'recurring', 'value' => true },
#       { 'type' => 'business_hours', 'value' => 'open'|'closed' },
#       { 'type' => 'schedule', 'weekdays' => [1, 2, 3, 4, 5], 'from' => '09:00', 'to' => '18:00' }
#     ] }
#
# Sem regras, a condição é verdadeira: uma etapa recém-criada não pode jogar
# todo mundo no "senão" antes de o operador terminar de configurá-la.
class Chatflow::ConditionEvaluator
  RULE_TYPES = %w[label attribute lead_source recurring business_hours schedule].freeze

  COMPARATORS = {
    'equals' => ->(text, expected) { text == expected },
    'not_equals' => ->(text, expected) { text != expected },
    'contains' => ->(text, expected) { expected.present? && text.include?(expected) },
    'present' => ->(text, _expected) { text.present? },
    'blank' => ->(text, _expected) { text.blank? },
    'greater' => ->(text, expected) { compare(text, expected) { |a, b| a > b } },
    'less' => ->(text, expected) { compare(text, expected) { |a, b| a < b } }
  }.freeze

  def self.compare(actual, expected)
    a = number(actual)
    b = number(expected)
    a && b ? yield(a, b) : false
  end

  def self.number(value)
    return nil if value.blank?

    Float(value.to_s.tr(',', '.'), exception: false)
  end

  def initialize(conversation, config, now: Time.current)
    @conversation = conversation
    @config = config.to_h
    @now = now
  end

  def handle
    match? ? ChatflowNode::TRUE_BRANCH : ChatflowNode::FALSE_BRANCH
  end

  def match?
    rules = Array(@config['rules']).select { |rule| RULE_TYPES.include?(rule.to_h['type']) }
    return true if rules.empty?

    results = rules.map { |rule| evaluate(rule.to_h) }
    @config['match'] == 'any' ? results.any? : results.all?
  end

  private

  def evaluate(rule)
    send(:"#{rule['type']}_rule", rule)
  end

  def label_rule(rule)
    titles = @conversation.account.labels.where(id: Array(rule['label_ids']).map(&:to_i)).pluck(:title)
    has = titles.intersect?(@conversation.label_list.to_a)
    rule['operator'] == 'not_has' ? !has : has
  end

  def attribute_rule(rule)
    text = attribute_value(rule['scope'], rule['key'].to_s).to_s.strip.downcase
    expected = rule['value'].to_s.strip.downcase
    COMPARATORS.fetch(rule['operator'].to_s, COMPARATORS['equals']).call(text, expected)
  end

  def attribute_value(scope, key)
    return @conversation.custom_attributes.to_h[key] if scope == 'conversation'

    contact = @conversation.contact
    return contact&.public_send(key) if Chatflow::AnswerCapture::CONTACT_FIELDS.include?(key)

    contact&.custom_attributes.to_h[key]
  end

  # Origem do lead: o atributo `origem_lead` do contato (primeiro toque vence),
  # e a conversa marcada pelo anúncio enquanto o atributo ainda não foi gravado.
  def lead_source_rule(rule)
    origin = @conversation.contact&.custom_attributes.to_h['origem_lead'].presence
    origin ||= 'anuncio_facebook' if @conversation.custom_attributes.to_h['anuncio_id'].present?
    origin ||= 'organico'
    origin == rule['value'].to_s
  end

  def recurring_rule(rule)
    recurring = @conversation.label_list.to_a.include?('cliente-recorrente') ||
                Conversations::RecurringCustomerService.recurring?(@conversation)
    ActiveModel::Type::Boolean.new.cast(rule.fetch('value', true)) ? recurring : !recurring
  end

  # Horário de funcionamento da caixa (o mesmo do "fora do expediente" do
  # Chatwoot). Caixa sem horário configurado conta como aberta.
  def business_hours_rule(rule)
    open = @conversation.inbox.working_now?
    rule['value'] == 'closed' ? !open : open
  end

  def schedule_rule(rule)
    local = @now.in_time_zone(zone)
    weekdays = Array(rule['weekdays']).map(&:to_i)
    return false if weekdays.any? && weekdays.exclude?(local.wday)

    minutes = (local.hour * 60) + local.min
    from = minutes_of(rule['from'], 0)
    to = minutes_of(rule['to'], 24 * 60)
    from <= to ? minutes.between?(from, to - 1) : (minutes >= from || minutes < to)
  end

  def minutes_of(value, fallback)
    hour, minute = value.to_s.split(':').map(&:to_i)
    value.present? ? (hour.to_i * 60) + minute.to_i : fallback
  end

  def zone
    name = @conversation.account.reporting_timezone.presence || Broadcasts::SendWindow::DEFAULT_TIMEZONE
    ActiveSupport::TimeZone[name] || ActiveSupport::TimeZone[Broadcasts::SendWindow::DEFAULT_TIMEZONE]
  end
end

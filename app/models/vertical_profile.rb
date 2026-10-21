# UniverZAP: how the product behaves for each service vertical — which status
# counts as a conversion in the panel, which label marks a returning customer,
# whether the customer sheet offers "Agendar" (and which status it applies),
# which conversation attributes the sheet shows instead of the salon's
# appointment fields, which ready-made AI agents fit and whether the Belezaki
# integration (a salon agenda) makes sense at all. Status names come from
# lib/vertical_templates/templates/<key>.yml.
#
# An account without a vertical keeps the original salon behaviour, which is
# what every account had before verticals existed — except the agent picker,
# which keeps showing every template. A vertical created from
# Super Admin without a profile here gets the neutral one: no conversion
# default, no returning-customer label, no scheduling.
class VerticalProfile
  SALON = {
    conversion_status: 'agendado',
    recurring_label: 'cliente-recorrente',
    schedule_status: 'agendado',
    sheet_fields: nil,
    agent_templates: %w[salao nails],
    belezaki: true
  }.freeze

  PROFILES = {
    'beauty_salon' => SALON,
    'healthcare_clinic' => {
      conversion_status: 'agendado',
      recurring_label: nil,
      schedule_status: 'agendado',
      sheet_fields: nil,
      agent_templates: %w[clinica],
      belezaki: false
    },
    'ecommerce' => {
      conversion_status: 'pedido-confirmado',
      recurring_label: 'comprou-novamente',
      schedule_status: nil,
      sheet_fields: %w[numero_pedido valor_pedido codigo_rastreio motivo_contato],
      agent_templates: %w[varejo],
      belezaki: false
    },
    'food_delivery' => {
      conversion_status: 'pedido-confirmado',
      recurring_label: nil,
      schedule_status: nil,
      sheet_fields: %w[numero_pedido itens_pedido endereco_entrega forma_pagamento],
      agent_templates: %w[varejo],
      belezaki: false
    },
    'real_estate' => {
      conversion_status: 'visita-agendada',
      recurring_label: nil,
      schedule_status: nil,
      sheet_fields: %w[tipo_interesse imovel_codigo faixa_orcamento corretor_responsavel],
      agent_templates: [],
      belezaki: false
    }
  }.freeze

  UNSET = SALON.merge(agent_templates: []).freeze

  NEUTRAL = { conversion_status: nil, recurring_label: nil, schedule_status: nil, sheet_fields: [], agent_templates: [], belezaki: false }.freeze

  attr_reader :key

  def self.for(account)
    new(account.custom_attributes&.dig('vertical_template'))
  end

  def initialize(key)
    @key = key.presence
    @profile = @key ? PROFILES.fetch(@key, NEUTRAL) : UNSET
  end

  def conversion_status = @profile[:conversion_status]
  def recurring_label = @profile[:recurring_label]
  def schedule_status = @profile[:schedule_status]
  def schedules? = schedule_status.present?

  # nil keeps the salon's appointment rows; a list replaces them.
  def sheet_fields = @profile[:sheet_fields]

  def belezaki? = @profile[:belezaki]

  # Empty means "no preference": the picker shows every template.
  def agent_templates = @profile[:agent_templates]

  def as_json(*)
    {
      key: key,
      conversion_status: conversion_status,
      recurring_label: recurring_label,
      schedule_status: schedule_status,
      sheet_fields: sheet_fields,
      agent_templates: agent_templates,
      belezaki: belezaki?
    }
  end
end

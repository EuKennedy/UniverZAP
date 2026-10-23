require 'rails_helper'

RSpec.describe VerticalProfile do
  def profile_for(vertical)
    described_class.for(build(:account, custom_attributes: vertical ? { 'vertical_template' => vertical } : {}))
  end

  it 'gives e-commerce its own conversion, returning-customer label and sheet, without scheduling', :aggregate_failures do
    profile = profile_for('ecommerce')

    expect(profile.conversion_status).to eq('pedido-confirmado')
    expect(profile.recurring_label).to eq('comprou-novamente')
    expect(profile.schedules?).to be(false)
    expect(profile.sheet_fields).to eq(%w[numero_pedido valor_pedido codigo_rastreio motivo_contato])
    expect(profile.agent_templates).to eq(%w[varejo])
    expect(profile.belezaki?).to be(false)
    expect(profile.store_connector?).to be(true)
  end

  it 'keeps the salon behaviour for salons', :aggregate_failures do
    profile = profile_for('beauty_salon')

    expect(profile.conversion_status).to eq('agendado')
    expect(profile.recurring_label).to eq('cliente-recorrente')
    expect(profile.schedule_status).to eq('agendado')
    expect(profile.sheet_fields).to be_nil
    expect(profile.agent_templates).to eq(%w[salao nails])
    expect(profile.belezaki?).to be(true)
    expect(profile.store_connector?).to be(false)
  end

  it 'keeps the salon behaviour for an account without a vertical, but no template preference', :aggregate_failures do
    profile = profile_for(nil)

    expect(profile.schedules?).to be(true)
    expect(profile.recurring_label).to eq('cliente-recorrente')
    expect(profile.agent_templates).to eq([])
  end

  it 'falls back to a neutral profile for a vertical it does not know', :aggregate_failures do
    profile = profile_for('pet_shop')

    expect(profile.conversion_status).to be_nil
    expect(profile.recurring_label).to be_nil
    expect(profile.schedules?).to be(false)
    expect(profile.sheet_fields).to eq([])
  end

  # Every status a profile names must exist in its vertical's template, or the
  # panel and the sheet would point at labels the account never gets.
  it 'only names statuses that the vertical template defines' do
    described_class::PROFILES.each do |key, profile|
      titles = YAML.safe_load(Rails.root.join("lib/vertical_templates/templates/#{key}.yml").read)['labels'].pluck('title')
      named = profile.values_at(:conversion_status, :recurring_label, :schedule_status).compact

      expect(titles).to include(*named), "#{key} names #{named - titles}"
    end
  end

  it 'only names sheet fields that the vertical template defines' do
    described_class::PROFILES.each do |key, profile|
      next if profile[:sheet_fields].nil?

      template = YAML.safe_load(Rails.root.join("lib/vertical_templates/templates/#{key}.yml").read)
      keys = template['custom_attribute_definitions'].pluck('attribute_key')
      expect(keys).to include(*profile[:sheet_fields]), key
    end
  end
end

# frozen_string_literal: true

FactoryBot.define do
  factory :whatsapp_status_post do
    account
    kind { 'text' }
    body { 'Agenda aberta para sábado' }
    background_color { '#0A5F55' }
    font { 0 }
    status { :draft }
    inbox_ids { [] }
  end

  factory :whatsapp_status_template do
    account
    sequence(:name) { |n| "Modelo #{n}" }
    body { 'Promoção de terça: escova com 20% off' }
    background_color { '#B03A2E' }
    font { 1 }
  end
end

FactoryBot.define do
  factory :whatsapp_status_folder do
    account
    sequence(:name) { |n| "Pasta #{n}" }
    color { '#8E44AD' }
  end

  factory :whatsapp_status_campaign do
    account
    sequence(:name) { |n| "Campanha #{n}" }
    color { '#B03A2E' }
    time_zone { 'America/Sao_Paulo' }
    inbox_ids { [] }
  end

  factory :whatsapp_status_campaign_step do
    campaign factory: :whatsapp_status_campaign
    kind { 'text' }
    body { 'Promoção de terça na {{conexao}}' }
    background_color { '#B03A2E' }
    time_of_day { '09:00' }
    day_offset { 0 }
  end
end

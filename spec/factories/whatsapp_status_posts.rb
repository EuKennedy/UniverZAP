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

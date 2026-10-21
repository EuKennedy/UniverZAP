# frozen_string_literal: true

FactoryBot.define do
  factory :contact_list do
    account
    sequence(:name) { |n| "Lista #{n}" }
    source { 'manual' }
  end

  factory :contact_list_member do
    contact_list
    contact
    status { :active }
  end
end

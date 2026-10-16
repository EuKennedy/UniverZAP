FactoryBot.define do
  factory :inbox_group do
    account
    sequence(:name) { |n| "Grupo #{n}" }
  end
end

FactoryBot.define do
  factory :ai_manager_check_setting, class: 'Ai::Manager::CheckSetting' do
    account
    check_key { 'loose_promise' }
    enabled { true }
  end
end

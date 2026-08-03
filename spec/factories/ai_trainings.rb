FactoryBot.define do
  factory :ai_training, class: 'Ai::Training' do
    account { ai_assistant.account }
    ai_assistant
    sequence(:title) { |n| "Documento #{n}" }
    source_type { 'text' }
    category { 'base' }
    status { 'ready' }
    content { 'Conteúdo de treino.' }
  end
end

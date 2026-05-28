# frozen_string_literal: true

FactoryBot.define do
  factory :task_comment do
    task
    user { association :user, account: task.account }
    body { { 'type' => 'doc', 'content' => [{ 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'hello' }] }] } }
  end
end

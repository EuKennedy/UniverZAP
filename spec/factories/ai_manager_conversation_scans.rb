FactoryBot.define do
  factory :ai_manager_conversation_scan, class: 'Ai::Manager::ConversationScan' do
    account
    # `running` é o padrão de propósito: é o estado em que a varredura nasce, e
    # um teste que precise dela terminada tem que dizer isso em voz alta.
    status { 'running' }
    # A janela padrão do produto, de sete dias: com 24h a varredura não alcança
    # a mensagem de quem já está esperando há mais de um dia.
    window_hours { 168 }
    started_at { Time.current }
    conversations_scanned { 0 }
    conversations_read { 0 }
    findings_count { 0 }
    cost_cents_brl { 0 }
    summary { {} }

    trait :done do
      status { 'done' }
      finished_at { Time.current }
      conversations_scanned { 120 }
      conversations_read { 43 }
      findings_count { 9 }
      cost_cents_brl { 74 }
      summary { { 'candidates' => 43, 'triage_findings' => 6, 'reading_findings' => 3 } }
    end
  end
end

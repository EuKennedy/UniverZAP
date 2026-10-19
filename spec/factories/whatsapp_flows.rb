FactoryBot.define do
  factory :whatsapp_flow do
    account
    inbox do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                validate_provider_config: false, sync_templates: false).inbox
    end
    sequence(:name) { |n| "Formulário #{n}" }
    category { 'APPOINTMENT_BOOKING' }
    status { 'draft' }
    field_mappings do
      { 'fields' => { 'servico' => { 'model' => 'conversation', 'key' => 'servico' },
                      'observacao' => { 'model' => 'contact', 'key' => 'observacao' } },
        'labels' => ['agendado'] }
    end
    flow_json do
      {
        'version' => '7.3',
        'screens' => [{
          'id' => 'AGENDAMENTO', 'title' => 'Agendar', 'terminal' => true,
          'layout' => { 'type' => 'SingleColumnLayout', 'children' => [
            { 'type' => 'TextHeading', 'text' => 'Vamos agendar?' },
            { 'type' => 'Form', 'name' => 'form', 'children' => [
              { 'type' => 'Dropdown', 'name' => 'servico', 'label' => 'Serviço', 'required' => true,
                'data-source' => [{ 'id' => 'corte', 'title' => 'Corte' }, { 'id' => 'coloracao', 'title' => 'Coloração' }] },
              { 'type' => 'TextArea', 'name' => 'observacao', 'label' => 'Observações' },
              { 'type' => 'Footer', 'label' => 'Enviar',
                'on-click-action' => { 'name' => 'complete', 'payload' => { 'servico' => '${form.servico}', 'observacao' => '${form.observacao}' } } }
            ] }
          ] }
        }]
      }
    end

    trait :published do
      status { 'published' }
      sequence(:meta_flow_id) { |n| "69124424266#{n}" }
      published_at { Time.current }
    end
  end
end

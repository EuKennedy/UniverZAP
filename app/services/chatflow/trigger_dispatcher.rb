# Gatilhos do Chatflow que não nascem de uma mensagem recebida: etiqueta
# adicionada, contato entrou numa lista. (Data é varrida pelo
# Chatflow::DateTriggerScanner; resposta a disparo é decidida na própria
# mensagem, pelo EngineService.)
#
# Fluxos candidatos: ativos, ou em modo de teste (só para o número do
# testador), da caixa da conversa ou de todas. Um por vez — o primeiro que
# casa, como no gatilho por mensagem.
class Chatflow::TriggerDispatcher
  def self.label_added(conversation, titles)
    return if conversation.blank? || titles.blank? || conversation.sandbox?

    label_ids = conversation.account.labels.where(title: titles).pluck(:id)
    return if label_ids.empty?

    flow = candidates(conversation.account, conversation.inbox_id).trigger_label_added
                                                                  .detect { |f| f.trigger_label_ids.intersect?(label_ids) }
    start(flow, conversation, 'trigger' => 'label_added')
  end

  def self.list_entered(list, contact)
    return if list.blank? || contact.blank?

    flows = candidates(contact.account, nil, any_inbox: true).trigger_list_entered.select do |flow|
      flow.trigger_list_ids.empty? || flow.trigger_list_ids.include?(list.id)
    end
    flows.find { |flow| start_on_latest(flow, contact, 'trigger' => 'list_entered', 'list_id' => list.id) }
  end

  def self.start_on_latest(flow, contact, context)
    conversation = latest_conversation(contact, flow.inbox_id)
    conversation && start(flow, conversation, context)
  end

  def self.candidates(account, inbox_id, any_inbox: false)
    scope = account.chatflows.where('status = ? OR test_mode = ?', Chatflow.statuses[:active], true)
    any_inbox ? scope : scope.where(inbox_id: [inbox_id, nil])
  end

  # A conversa mais recente do contato (na caixa do fluxo, quando ele tem uma).
  # Sem conversa não há por onde falar com a cliente — o gatilho é ignorado.
  def self.latest_conversation(contact, inbox_id)
    scope = contact.conversations
    scope = scope.where(inbox_id: inbox_id) if inbox_id
    scope.order(last_activity_at: :desc, id: :desc).first
  end

  def self.start(flow, conversation, context)
    return if flow.nil?

    Chatflow::EngineService.new(nil, conversation: conversation).start_from_event(flow, context: context)
  end
end

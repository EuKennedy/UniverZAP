class KanbanAutomationListener < BaseListener
  def conversation_created(event)
    conversation, _account = extract_conversation_and_account(event)
    Kanban::AutomationService.handle_conversation_created(conversation)
  end

  def conversation_resolved(event)
    conversation, _account = extract_conversation_and_account(event)
    Kanban::AutomationService.handle_conversation_resolved(conversation)
  end

  def assignee_changed(event)
    conversation, _account = extract_conversation_and_account(event)
    Kanban::AutomationService.handle_assignee_changed(conversation)
  end
end

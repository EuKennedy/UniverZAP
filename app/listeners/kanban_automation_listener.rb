class KanbanAutomationListener < BaseListener
  def conversation_created(event)
    return if sandbox_event?(event)

    conversation, _account = extract_conversation_and_account(event)
    Kanban::AutomationService.handle_conversation_created(conversation)
  end

  def conversation_resolved(event)
    return if sandbox_event?(event)

    conversation, _account = extract_conversation_and_account(event)
    Kanban::AutomationService.handle_conversation_resolved(conversation)
  end

  def assignee_changed(event)
    return if sandbox_event?(event)

    conversation, _account = extract_conversation_and_account(event)
    Kanban::AutomationService.handle_assignee_changed(conversation)
  end
end

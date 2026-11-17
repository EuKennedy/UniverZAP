class MessageFinder
  def initialize(conversation, params)
    @conversation = conversation
    @params = params
  end

  def perform
    current_messages
  end

  private

  def conversation_messages
    @conversation.messages.includes(:attachments, :sender, sender: { avatar_attachment: [:blob] })
  end

  def messages
    return conversation_messages if @params[:filter_internal_messages].blank?

    conversation_messages.where.not('private = ? OR message_type = ?', true, 2)
  end

  def current_messages
    if @params[:after].present? && @params[:before].present?
      messages_between(@params[:after].to_i, @params[:before].to_i)
    elsif @params[:before].present?
      messages_before(@params[:before].to_i)
    elsif @params[:after].present?
      messages_after(@params[:after].to_i)
    else
      messages_latest
    end
  end

  def messages_after(after_id)
    messages.reorder('created_at asc').where('id > ?', after_id).limit(100)
  end

  # A data decide o que vem antes, não o id: mensagem que entra atrasada (WAHA
  # reprocessada, importação) nasce com id alto e data antiga, e o corte por id
  # a escondia para sempre da conversa.
  def messages_before(before_id)
    messages_older_than(before_id).reorder('messages.created_at desc, messages.id desc').limit(20).reverse
  end

  def messages_older_than(before_id)
    anchor = @conversation.messages.find_by(id: before_id)
    return messages.where('messages.id < ?', before_id) if anchor.blank?

    messages.where(
      'messages.created_at < :created_at OR (messages.created_at = :created_at AND messages.id < :id)',
      created_at: anchor.created_at, id: anchor.id
    )
  end

  def messages_between(after_id, before_id)
    messages.reorder('created_at asc').where('id >= ? AND id < ?', after_id, before_id).limit(1000)
  end

  def messages_latest
    messages.reorder('created_at desc').limit(20).reverse
  end
end

MessageFinder.prepend_mod_with('MessageFinder')

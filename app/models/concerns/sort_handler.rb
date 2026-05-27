module SortHandler
  extend ActiveSupport::Concern

  class_methods do
    # Per-model order-by prefix prepended to every sort scope. Models
    # with no special precedence (e.g. Mention) return an empty string;
    # Conversation overrides this to float pinned chats to the top with
    # `pinned_at IS NULL, pinned_at DESC, …`. Encapsulating the prefix
    # behind a hook keeps the concern reusable for any model that wants
    # its own "stick this on top" rule later.
    def sort_prefix
      ''
    end

    def sort_on_last_activity_at(sort_direction = :desc)
      order(generate_sql_query("#{sort_prefix}last_activity_at #{sort_direction.to_s.upcase}"))
    end

    def sort_on_created_at(sort_direction = :asc)
      order(generate_sql_query("#{sort_prefix}created_at #{sort_direction.to_s.upcase}"))
    end

    def sort_on_priority(sort_direction = :desc)
      order(generate_sql_query("#{sort_prefix}priority #{sort_direction.to_s.upcase} NULLS LAST, last_activity_at DESC"))
    end

    def sort_on_priority_created_at(sort_direction = :desc)
      order(generate_sql_query("#{sort_prefix}priority #{sort_direction.to_s.upcase} NULLS LAST, created_at ASC"))
    end

    def sort_on_waiting_since(sort_direction = :asc)
      order(generate_sql_query(
              "#{sort_prefix}(waiting_since IS NULL), waiting_since #{sort_direction.to_s.upcase}, created_at ASC"
            ))
    end

    def last_messaged_conversations
      Message.except(:order).select(
        'DISTINCT ON (conversation_id) conversation_id, id, created_at, message_type'
      ).order('conversation_id, created_at DESC')
    end

    def sort_on_last_user_message_at
      order('grouped_conversations.message_type', 'grouped_conversations.created_at ASC')
    end

    private

    def generate_sql_query(query)
      Arel::Nodes::SqlLiteral.new(sanitize_sql_for_order(query))
    end
  end
end

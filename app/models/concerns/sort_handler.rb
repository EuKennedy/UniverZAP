module SortHandler
  extend ActiveSupport::Concern

  class_methods do
    # Pinned conversations float to the very top regardless of the
    # active sort. We prepend a stable `pinned_at IS NULL` clause to
    # every sort so a pinned chat always sits above unpinned peers
    # without changing existing sort semantics for the rest of the
    # list. Among multiple pinned chats, most-recently-pinned wins.
    PINNED_FIRST_PREFIX = 'pinned_at IS NULL, pinned_at DESC'.freeze

    def sort_on_last_activity_at(sort_direction = :desc)
      order(generate_sql_query("#{PINNED_FIRST_PREFIX}, last_activity_at #{sort_direction.to_s.upcase}"))
    end

    def sort_on_created_at(sort_direction = :asc)
      order(generate_sql_query("#{PINNED_FIRST_PREFIX}, created_at #{sort_direction.to_s.upcase}"))
    end

    def sort_on_priority(sort_direction = :desc)
      order(generate_sql_query("#{PINNED_FIRST_PREFIX}, priority #{sort_direction.to_s.upcase} NULLS LAST, last_activity_at DESC"))
    end

    def sort_on_priority_created_at(sort_direction = :desc)
      order(generate_sql_query("#{PINNED_FIRST_PREFIX}, priority #{sort_direction.to_s.upcase} NULLS LAST, created_at ASC"))
    end

    def sort_on_waiting_since(sort_direction = :asc)
      order(generate_sql_query("#{PINNED_FIRST_PREFIX}, (waiting_since IS NULL), waiting_since #{sort_direction.to_s.upcase}, created_at ASC"))
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

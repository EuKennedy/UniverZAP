class CreateTeamChat < ActiveRecord::Migration[7.1]
  # Internal team chat — Slack/Discord-style channels scoped to an account.
  # Two tables ship together (channels + messages) because the feature is
  # meaningless with only one; splitting would force a deploy ordering on
  # Coolify with no payoff.
  #
  # Deliberately NOT modeled:
  #   - per-user membership / unread cursors — the whole team sees every
  #     channel (internal tool, small headcount); we can layer a
  #     `team_chat_reads` table later without touching these.
  #   - rich-text jsonb — messages are plain text (Slack-style line breaks
  #     + @mention highlighting done client-side); keeps the payload light
  #     and the composer trivial. Can migrate to jsonb if formatting lands.
  # rubocop:disable Metrics/MethodLength
  def change
    create_table :team_chat_channels do |t|
      t.references :account, null: false, foreign_key: true, index: true
      # Nullable: default channels are seeded by the system (no creator).
      t.references :created_by_user, foreign_key: { to_table: :users }

      t.string :name, null: false, limit: 80
      # URL/anchor-safe identifier shown as `#slug` in the UI. Unique per
      # account so two channels can't collide on the same handle.
      t.string :slug, null: false, limit: 80
      t.text :description

      # default → the four seeded channels (geral/discussoes/metas/
      # comunicados); custom → anything an admin adds via the "+" button.
      # Drives whether the channel can be renamed/deleted in the UI.
      t.integer :kind, null: false, default: 0
      t.integer :position, null: false, default: 0
      # Soft-delete: archiving hides a channel without nuking its history.
      t.datetime :archived_at

      t.timestamps
    end

    add_index :team_chat_channels, %i[account_id slug], unique: true
    add_index :team_chat_channels, %i[account_id position]

    create_table :team_chat_messages do |t|
      t.references :channel, null: false,
                             foreign_key: { to_table: :team_chat_channels },
                             index: true
      t.references :user, null: false, foreign_key: true, index: true

      t.text :content, null: false
      # Stamped when the author edits — drives the "(editado)" marker.
      t.datetime :edited_at

      t.timestamps
    end

    # Hot path: paginated message history for a channel, newest first.
    add_index :team_chat_messages, %i[channel_id created_at]
  end
  # rubocop:enable Metrics/MethodLength
end

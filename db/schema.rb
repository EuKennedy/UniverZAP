# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_10_21_100000) do
  # These extensions should be enabled to support this database
  enable_extension "pg_stat_statements"
  enable_extension "pg_trgm"
  enable_extension "pgcrypto"
  enable_extension "plpgsql"
  enable_extension "vector"

  create_table "access_tokens", force: :cascade do |t|
    t.string "owner_type"
    t.bigint "owner_id"
    t.string "token"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_type", "owner_id"], name: "index_access_tokens_on_owner_type_and_owner_id"
    t.index ["token"], name: "index_access_tokens_on_token", unique: true
  end

  create_table "account_saml_settings", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "sso_url"
    t.text "certificate"
    t.string "sp_entity_id"
    t.string "idp_entity_id"
    t.json "role_mappings", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_account_saml_settings_on_account_id"
  end

  create_table "account_users", force: :cascade do |t|
    t.bigint "account_id"
    t.bigint "user_id"
    t.integer "role", default: 0
    t.bigint "inviter_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "active_at", precision: nil
    t.integer "availability", default: 0, null: false
    t.boolean "auto_offline", default: true, null: false
    t.bigint "custom_role_id"
    t.bigint "agent_capacity_policy_id"
    t.index ["account_id", "user_id"], name: "uniq_user_id_per_account_id", unique: true
    t.index ["account_id"], name: "index_account_users_on_account_id"
    t.index ["agent_capacity_policy_id"], name: "index_account_users_on_agent_capacity_policy_id"
    t.index ["custom_role_id"], name: "index_account_users_on_custom_role_id"
    t.index ["user_id"], name: "index_account_users_on_user_id"
  end

  create_table "accounts", id: :serial, force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "locale", default: 0
    t.string "domain", limit: 100
    t.string "support_email", limit: 100
    t.bigint "feature_flags", default: 0, null: false
    t.integer "auto_resolve_duration"
    t.jsonb "limits", default: {}
    t.jsonb "custom_attributes", default: {}
    t.integer "status", default: 0
    t.jsonb "internal_attributes", default: {}, null: false
    t.jsonb "settings", default: {}
    t.integer "token_credit_balance_cents_brl", default: 2500, null: false
    t.integer "token_credit_lifetime_purchased_cents_brl", default: 0, null: false
    t.boolean "token_credit_grace_used", default: false, null: false
    t.index ["status"], name: "index_accounts_on_status"
    t.index ["token_credit_balance_cents_brl"], name: "index_accounts_on_token_credit_balance_cents_brl"
  end

  create_table "action_mailbox_inbound_emails", force: :cascade do |t|
    t.integer "status", default: 0, null: false
    t.string "message_id", null: false
    t.string "message_checksum", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id", "message_checksum"], name: "index_action_mailbox_inbound_emails_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", precision: nil, null: false
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "agent_bot_inboxes", force: :cascade do |t|
    t.integer "inbox_id"
    t.integer "agent_bot_id"
    t.integer "status", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "account_id"
  end

  create_table "agent_bots", force: :cascade do |t|
    t.string "name"
    t.string "description"
    t.string "outgoing_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "account_id"
    t.integer "bot_type", default: 0
    t.jsonb "bot_config", default: {}
    t.string "secret"
    t.index ["account_id"], name: "index_agent_bots_on_account_id"
  end

  create_table "agent_capacity_policies", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", limit: 255, null: false
    t.text "description"
    t.jsonb "exclusion_rules", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_agent_capacity_policies_on_account_id"
  end

  create_table "ai_ab_comparisons", force: :cascade do |t|
    t.bigint "ai_invocation_id", null: false
    t.bigint "ai_prompt_version_id", null: false
    t.bigint "ai_assistant_id", null: false
    t.bigint "account_id", null: false
    t.text "response_b"
    t.jsonb "telemetry_b", default: {}, null: false
    t.string "winner"
    t.boolean "critical_loss", default: false, null: false
    t.bigint "reviewer_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_ai_ab_comparisons_on_account_id"
    t.index ["ai_assistant_id"], name: "index_ai_ab_comparisons_on_ai_assistant_id"
    t.index ["ai_invocation_id", "ai_prompt_version_id"], name: "index_ai_ab_unique_duel", unique: true
    t.index ["ai_invocation_id"], name: "index_ai_ab_comparisons_on_ai_invocation_id"
    t.index ["ai_prompt_version_id", "winner"], name: "index_ai_ab_comparisons_on_ai_prompt_version_id_and_winner"
    t.index ["ai_prompt_version_id"], name: "index_ai_ab_comparisons_on_ai_prompt_version_id"
  end

  create_table "ai_assistants", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", limit: 80, null: false
    t.string "role", limit: 60, default: "Assistente"
    t.text "description"
    t.string "avatar_url"
    t.string "tone", limit: 40, default: "friendly"
    t.string "provider", default: "anthropic", null: false
    t.string "model", default: "claude-sonnet-4-5", null: false
    t.text "system_prompt"
    t.float "temperature", default: 0.3, null: false
    t.integer "max_tokens", default: 1024, null: false
    t.text "encrypted_anthropic_key"
    t.text "encrypted_openai_key"
    t.jsonb "router_config", default: {"eco" => "claude-haiku-4-5", "mid" => "claude-sonnet-4-5", "pro" => "claude-opus-4-5", "enabled" => false}, null: false
    t.boolean "autopilot_enabled", default: false, null: false
    t.jsonb "guardrails", default: {"stop_words" => ["humano", "atendente"], "business_hours" => nil, "max_messages_per_minute" => 4}, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "encrypted_elevenlabs_key"
    t.jsonb "behavior_flags", default: {}, null: false
    t.string "conversation_display_name"
    t.string "purpose", default: "attendance", null: false
    t.index ["account_id", "active"], name: "index_ai_assistants_on_account_id_and_active"
    t.index ["account_id", "name"], name: "index_ai_assistants_on_account_id_and_name", unique: true
    t.index ["account_id", "purpose"], name: "index_ai_assistants_on_account_id_and_purpose"
    t.index ["account_id"], name: "index_ai_assistants_on_account_id"
  end

  create_table "ai_belezaki_connections", force: :cascade do |t|
    t.bigint "ai_assistant_id", null: false
    t.bigint "account_id", null: false
    t.string "external_id", null: false
    t.string "salon_name"
    t.string "timezone", default: "America/Sao_Paulo", null: false
    t.string "status", default: "active", null: false
    t.datetime "connected_at"
    t.text "last_error"
    t.datetime "last_error_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_assistant_id"], name: "index_ai_belezaki_connections_on_ai_assistant_id", unique: true
  end

  create_table "ai_calendar_appointment_services", force: :cascade do |t|
    t.bigint "ai_calendar_appointment_id", null: false
    t.bigint "ai_calendar_service_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_calendar_appointment_id", "ai_calendar_service_id"], name: "idx_calendar_appt_service", unique: true
    t.index ["ai_calendar_service_id"], name: "idx_calendar_appt_service_on_service"
  end

  create_table "ai_calendar_appointments", force: :cascade do |t|
    t.bigint "ai_calendar_professional_id", null: false
    t.bigint "ai_assistant_id", null: false
    t.bigint "account_id", null: false
    t.bigint "contact_id", null: false
    t.bigint "conversation_id"
    t.string "google_event_id", null: false
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.string "status", default: "booked", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_calendar_professional_id", "starts_at"], name: "idx_calendar_appt_on_pro_start"
    t.index ["contact_id", "status"], name: "idx_calendar_appt_on_contact_status"
    t.index ["google_event_id"], name: "idx_calendar_appt_on_event", unique: true
  end

  create_table "ai_calendar_connections", force: :cascade do |t|
    t.bigint "ai_assistant_id", null: false
    t.bigint "account_id", null: false
    t.string "google_email", null: false
    t.text "encrypted_refresh_token", null: false
    t.string "status", default: "active", null: false
    t.datetime "last_error_at"
    t.string "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_ai_calendar_connections_on_account_id"
    t.index ["ai_assistant_id", "status"], name: "index_ai_calendar_connections_on_ai_assistant_id_and_status"
  end

  create_table "ai_calendar_hours", force: :cascade do |t|
    t.bigint "ai_calendar_professional_id", null: false
    t.bigint "account_id", null: false
    t.integer "weekday", null: false
    t.time "starts_at", null: false
    t.time "ends_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_calendar_professional_id", "weekday"], name: "idx_calendar_hours_on_pro_weekday"
  end

  create_table "ai_calendar_professionals", force: :cascade do |t|
    t.bigint "ai_calendar_connection_id", null: false
    t.bigint "ai_assistant_id", null: false
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.string "calendar_id", null: false
    t.string "timezone", default: "America/Sao_Paulo", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_assistant_id", "active"], name: "index_ai_calendar_professionals_on_ai_assistant_id_and_active"
    t.index ["ai_calendar_connection_id", "calendar_id"], name: "idx_calendar_pro_on_conn_calendar", unique: true
  end

  create_table "ai_calendar_service_professionals", force: :cascade do |t|
    t.bigint "ai_calendar_service_id", null: false
    t.bigint "ai_calendar_professional_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_calendar_professional_id"], name: "idx_calendar_service_pro_on_pro"
    t.index ["ai_calendar_service_id", "ai_calendar_professional_id"], name: "idx_calendar_service_pro", unique: true
  end

  create_table "ai_calendar_services", force: :cascade do |t|
    t.bigint "ai_assistant_id", null: false
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.integer "duration_minutes", null: false
    t.integer "price_cents"
    t.integer "buffer_minutes", default: 0, null: false
    t.boolean "global", default: true, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_assistant_id", "active"], name: "index_ai_calendar_services_on_ai_assistant_id_and_active"
  end

  create_table "ai_calendar_settings", force: :cascade do |t|
    t.bigint "ai_assistant_id", null: false
    t.bigint "account_id", null: false
    t.integer "minimum_lead_minutes", default: 120, null: false
    t.integer "horizon_days", default: 60, null: false
    t.integer "cancellation_window_hours", default: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_assistant_id"], name: "index_ai_calendar_settings_on_ai_assistant_id", unique: true
  end

  create_table "ai_chat_messages", force: :cascade do |t|
    t.bigint "ai_chat_thread_id", null: false
    t.bigint "account_id", null: false
    t.string "role", limit: 20, null: false
    t.text "content", null: false
    t.integer "input_tokens", default: 0
    t.integer "output_tokens", default: 0
    t.float "cost_usd", default: 0.0
    t.string "model"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.float "cost_brl", default: 0.0
    t.index ["account_id"], name: "index_ai_chat_messages_on_account_id"
    t.index ["ai_chat_thread_id", "created_at"], name: "index_ai_chat_messages_on_thread_created"
    t.index ["ai_chat_thread_id"], name: "index_ai_chat_messages_on_ai_chat_thread_id"
  end

  create_table "ai_chat_threads", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.bigint "ai_assistant_id", null: false
    t.bigint "conversation_id"
    t.string "title", limit: 180, null: false
    t.datetime "last_activity_at", null: false
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "user_id", "last_activity_at"], name: "index_ai_chat_threads_on_account_user_activity"
    t.index ["account_id"], name: "index_ai_chat_threads_on_account_id"
    t.index ["ai_assistant_id"], name: "index_ai_chat_threads_on_ai_assistant_id"
    t.index ["conversation_id", "user_id"], name: "index_ai_chat_threads_on_conversation_user", where: "(conversation_id IS NOT NULL)"
    t.index ["conversation_id"], name: "index_ai_chat_threads_on_conversation_id"
    t.index ["user_id"], name: "index_ai_chat_threads_on_user_id"
  end

  create_table "ai_credit_ledger_entries", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "kind", limit: 16, null: false
    t.integer "amount_cents_brl", null: false
    t.bigint "ai_invocation_id"
    t.string "external_payment_id"
    t.string "description", limit: 200
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "kind", "created_at"], name: "idx_on_account_id_kind_created_at_3f9e58deb0"
    t.index ["account_id"], name: "index_ai_credit_ledger_entries_on_account_id"
    t.index ["ai_invocation_id"], name: "index_ai_credit_ledger_entries_on_ai_invocation_id"
    t.index ["external_payment_id"], name: "index_ai_credit_ledger_entries_on_external_payment_id", unique: true, where: "(external_payment_id IS NOT NULL)"
  end

  create_table "ai_custom_tools", force: :cascade do |t|
    t.bigint "ai_assistant_id", null: false
    t.bigint "account_id", null: false
    t.string "title", null: false
    t.string "slug", null: false
    t.text "description"
    t.text "endpoint_url", null: false
    t.string "http_method", default: "GET", null: false
    t.string "auth_type", default: "none", null: false
    t.jsonb "auth_config", default: {}, null: false
    t.jsonb "param_schema", default: [], null: false
    t.text "request_template"
    t.text "response_template"
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_assistant_id", "enabled"], name: "index_ai_custom_tools_on_ai_assistant_id_and_enabled"
    t.index ["ai_assistant_id", "slug"], name: "index_ai_custom_tools_on_ai_assistant_id_and_slug", unique: true
  end

  create_table "ai_intents", force: :cascade do |t|
    t.bigint "ai_assistant_id", null: false
    t.bigint "account_id", null: false
    t.string "name", limit: 80, null: false
    t.string "triggers"
    t.string "action", null: false
    t.jsonb "action_payload", default: {}, null: false
    t.boolean "active", default: true, null: false
    t.integer "position", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_ai_intents_on_account_id"
    t.index ["ai_assistant_id", "active", "position"], name: "index_ai_intents_on_ai_assistant_id_and_active_and_position"
    t.index ["ai_assistant_id"], name: "index_ai_intents_on_ai_assistant_id"
  end

  create_table "ai_invocations", force: :cascade do |t|
    t.bigint "ai_assistant_id", null: false
    t.bigint "account_id", null: false
    t.bigint "conversation_id"
    t.bigint "message_id"
    t.string "phase", default: "main", null: false
    t.string "model", null: false
    t.integer "input_tokens", default: 0
    t.integer "output_tokens", default: 0
    t.integer "cache_read_tokens", default: 0
    t.integer "cache_write_tokens", default: 0
    t.float "cost_usd", default: 0.0
    t.integer "duration_ms", default: 0
    t.string "status", default: "success"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "system_prompt"
    t.text "user_message"
    t.text "ai_response"
    t.jsonb "chunks_used", default: [], null: false
    t.string "prompt_version"
    t.bigint "trigger_message_id"
    t.float "confidence"
    t.string "auto_flag"
    t.jsonb "auto_flags", default: [], null: false
    t.boolean "handoff", default: false, null: false
    t.string "delivery_status"
    t.decimal "cost_brl", precision: 12, scale: 6, default: "0.0", null: false
    t.boolean "sandbox", default: false, null: false
    t.index ["account_id", "created_at"], name: "index_ai_invocations_on_account_id_and_created_at"
    t.index ["account_id"], name: "index_ai_invocations_on_account_id"
    t.index ["ai_assistant_id", "auto_flag", "created_at"], name: "index_ai_invocations_on_flag_queue", where: "((auto_flag IS NOT NULL) AND (sandbox = false))"
    t.index ["ai_assistant_id", "created_at"], name: "index_ai_invocations_on_ai_assistant_id_and_created_at"
    t.index ["ai_assistant_id", "created_at"], name: "index_ai_invocations_on_undelivered", where: "((delivery_status)::text = 'pending'::text)"
    t.index ["ai_assistant_id"], name: "index_ai_invocations_on_ai_assistant_id"
    t.index ["conversation_id"], name: "index_ai_invocations_on_conversation_id"
    t.index ["phase", "model", "created_at"], name: "index_ai_invocations_on_phase_and_model_and_created_at"
    t.index ["trigger_message_id"], name: "index_ai_invocations_on_trigger_message_id", where: "(trigger_message_id IS NOT NULL)"
  end

  create_table "ai_lead_opportunities", force: :cascade do |t|
    t.bigint "ai_assistant_id", null: false
    t.bigint "account_id", null: false
    t.bigint "contact_id", null: false
    t.bigint "conversation_id"
    t.string "interest"
    t.decimal "potential_brl", precision: 12, scale: 2, default: "0.0", null: false
    t.integer "temperature", default: 0, null: false
    t.string "block_reason"
    t.string "suggested_action"
    t.string "status", default: "open", null: false
    t.decimal "won_brl", precision: 12, scale: 2
    t.datetime "last_seen_at", null: false
    t.datetime "followed_up_at"
    t.jsonb "signals", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "contact_id"], name: "index_ai_lead_opportunities_on_account_id_and_contact_id"
    t.index ["account_id"], name: "index_ai_lead_opportunities_on_account_id"
    t.index ["ai_assistant_id", "status", "temperature"], name: "idx_on_ai_assistant_id_status_temperature_040b70b7cc"
    t.index ["ai_assistant_id"], name: "index_ai_lead_opportunities_on_ai_assistant_id"
    t.index ["conversation_id"], name: "index_ai_lead_opportunities_on_conversation_id", unique: true, where: "(conversation_id IS NOT NULL)"
  end

  create_table "ai_manager_check_settings", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "check_key", null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "check_key"], name: "index_ai_manager_check_settings_on_account_id_and_check_key", unique: true
  end

  create_table "ai_manager_conversation_findings", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "scan_id"
    t.bigint "conversation_id", null: false
    t.integer "conversation_display_id"
    t.bigint "contact_id"
    t.bigint "ai_assistant_id"
    t.string "case_key", null: false
    t.string "severity", default: "medium", null: false
    t.string "title", null: false
    t.text "detail"
    t.text "excerpt"
    t.string "author", default: "none", null: false
    t.string "source", default: "triage", null: false
    t.integer "value_cents_brl", default: 0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.datetime "waiting_since"
    t.datetime "last_seen_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "author", "occurred_at"], name: "idx_manager_findings_account_author"
    t.index ["account_id", "conversation_id", "case_key"], name: "idx_manager_findings_unique_case", unique: true
    t.index ["account_id", "occurred_at"], name: "idx_manager_findings_account_occurred"
    t.index ["conversation_id"], name: "idx_manager_findings_conversation"
  end

  create_table "ai_manager_conversation_scans", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id"
    t.string "status", default: "running", null: false
    t.integer "window_hours", default: 24, null: false
    t.datetime "started_at"
    t.datetime "finished_at"
    t.integer "conversations_scanned", default: 0, null: false
    t.integer "conversations_read", default: 0, null: false
    t.integer "findings_count", default: 0, null: false
    t.integer "cost_cents_brl", default: 0, null: false
    t.jsonb "summary", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "created_at"], name: "idx_on_account_id_created_at_8710b121c0"
  end

  create_table "ai_manager_runs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id"
    t.string "status", default: "running", null: false
    t.string "triggered_by", default: "schedule", null: false
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "period_start"
    t.datetime "period_end"
    t.integer "conversations_analysed", default: 0, null: false
    t.integer "cost_cents_brl", default: 0, null: false
    t.jsonb "summary", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "created_at"], name: "index_ai_manager_runs_on_account_id_and_created_at"
  end

  create_table "ai_manager_suggestions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "ai_assistant_id", null: false
    t.bigint "ai_manager_run_id", null: false
    t.string "check_key", null: false
    t.string "severity", default: "normal", null: false
    t.string "title", null: false
    t.text "rationale"
    t.jsonb "evidence", default: {}, null: false
    t.string "target", null: false
    t.jsonb "proposed", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.datetime "applied_at"
    t.string "dismissed_reason"
    t.bigint "ai_prompt_version_id"
    t.bigint "ai_training_id"
    t.jsonb "outcome", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "ai_assistant_id", "check_key"], name: "index_ai_manager_suggestions_unique_open", unique: true, where: "((status)::text = ANY ((ARRAY['pending'::character varying, 'approved'::character varying])::text[]))"
    t.index ["account_id", "status", "created_at"], name: "idx_on_account_id_status_created_at_5a1e58bc58"
    t.index ["ai_assistant_id", "status"], name: "index_ai_manager_suggestions_on_ai_assistant_id_and_status"
    t.index ["ai_manager_run_id", "ai_assistant_id", "check_key"], name: "index_ai_manager_suggestions_unique_finding", unique: true
  end

  create_table "ai_prompt_versions", force: :cascade do |t|
    t.bigint "ai_assistant_id", null: false
    t.bigint "account_id", null: false
    t.string "version", null: false
    t.text "system_prompt"
    t.jsonb "few_shots", default: [], null: false
    t.jsonb "learnings", default: [], null: false
    t.string "status", default: "draft", null: false
    t.float "win_rate"
    t.datetime "promoted_at"
    t.datetime "archived_at"
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_ai_prompt_versions_on_account_id"
    t.index ["ai_assistant_id", "version"], name: "index_ai_prompt_versions_on_ai_assistant_id_and_version", unique: true
    t.index ["ai_assistant_id"], name: "index_ai_prompt_versions_on_ai_assistant_id"
    t.index ["ai_assistant_id"], name: "index_ai_prompt_versions_one_live", unique: true, where: "((status)::text = 'live'::text)"
  end

  create_table "ai_response_feedbacks", force: :cascade do |t|
    t.bigint "ai_invocation_id", null: false
    t.bigint "ai_assistant_id", null: false
    t.bigint "account_id", null: false
    t.bigint "reviewer_id", null: false
    t.string "rating", null: false
    t.string "reason"
    t.text "corrected_text"
    t.datetime "applied_at"
    t.bigint "ai_training_id"
    t.bigint "ai_intent_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_ai_response_feedbacks_on_account_id"
    t.index ["ai_assistant_id", "created_at"], name: "index_ai_response_feedbacks_on_ai_assistant_id_and_created_at"
    t.index ["ai_assistant_id"], name: "index_ai_response_feedbacks_on_ai_assistant_id"
    t.index ["ai_invocation_id", "reviewer_id"], name: "index_ai_feedback_unique_reviewer", unique: true
    t.index ["ai_invocation_id"], name: "index_ai_response_feedbacks_on_ai_invocation_id"
  end

  create_table "ai_response_histories", force: :cascade do |t|
    t.bigint "ai_assistant_id", null: false
    t.bigint "account_id", null: false
    t.bigint "conversation_id"
    t.bigint "message_id"
    t.text "user_message"
    t.text "ai_response"
    t.string "model"
    t.string "auto_flag"
    t.float "confidence"
    t.decimal "cost_brl", precision: 12, scale: 6, default: "0.0", null: false
    t.float "cost_usd", default: 0.0, null: false
    t.integer "duration_ms", default: 0, null: false
    t.integer "calls", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_assistant_id", "created_at"], name: "index_ai_response_histories_on_ai_assistant_id_and_created_at"
    t.index ["ai_assistant_id", "message_id"], name: "index_ai_response_histories_on_ai_assistant_id_and_message_id", unique: true
  end

  create_table "ai_revenue_events", force: :cascade do |t|
    t.bigint "ai_assistant_id", null: false
    t.bigint "account_id", null: false
    t.bigint "conversation_id"
    t.bigint "contact_id"
    t.bigint "ai_lead_opportunity_id"
    t.string "source", null: false
    t.decimal "amount_brl", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "occurred_at", null: false
    t.string "external_ref"
    t.string "recorded_by", default: "operator", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "external_ref"], name: "index_ai_revenue_events_on_account_id_and_external_ref", unique: true, where: "(external_ref IS NOT NULL)"
    t.index ["account_id"], name: "index_ai_revenue_events_on_account_id"
    t.index ["ai_assistant_id", "occurred_at"], name: "index_ai_revenue_events_on_ai_assistant_id_and_occurred_at"
    t.index ["ai_assistant_id"], name: "index_ai_revenue_events_on_ai_assistant_id"
    t.index ["conversation_id"], name: "index_ai_revenue_events_on_conversation_id"
  end

  create_table "ai_trainings", force: :cascade do |t|
    t.bigint "ai_assistant_id", null: false
    t.bigint "account_id", null: false
    t.string "title", limit: 180, null: false
    t.string "source_type", null: false
    t.string "category", limit: 40, default: "base"
    t.text "content"
    t.integer "char_count", default: 0
    t.string "status", limit: 20, default: "pending"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_ai_trainings_on_account_id"
    t.index ["ai_assistant_id", "category", "status"], name: "index_ai_trainings_on_ai_assistant_id_and_category_and_status"
    t.index ["ai_assistant_id", "status"], name: "index_ai_trainings_on_ai_assistant_id_and_status"
    t.index ["ai_assistant_id"], name: "index_ai_trainings_on_ai_assistant_id"
  end

  create_table "applied_slas", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "sla_policy_id", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "sla_status", default: 0
    t.index ["account_id", "sla_policy_id", "conversation_id"], name: "index_applied_slas_on_account_sla_policy_conversation", unique: true
    t.index ["account_id"], name: "index_applied_slas_on_account_id"
    t.index ["conversation_id"], name: "index_applied_slas_on_conversation_id"
    t.index ["sla_policy_id"], name: "index_applied_slas_on_sla_policy_id"
  end

  create_table "article_embeddings", force: :cascade do |t|
    t.bigint "article_id", null: false
    t.text "term", null: false
    t.vector "embedding", limit: 1536
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["embedding"], name: "index_article_embeddings_on_embedding", using: :ivfflat
  end

  create_table "articles", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "portal_id", null: false
    t.integer "category_id"
    t.integer "folder_id"
    t.string "title"
    t.text "description"
    t.text "content"
    t.integer "status"
    t.integer "views"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "author_id"
    t.bigint "associated_article_id"
    t.jsonb "meta", default: {}
    t.string "slug", null: false
    t.integer "position"
    t.string "locale", default: "en", null: false
    t.index ["account_id"], name: "index_articles_on_account_id"
    t.index ["associated_article_id"], name: "index_articles_on_associated_article_id"
    t.index ["author_id"], name: "index_articles_on_author_id"
    t.index ["portal_id"], name: "index_articles_on_portal_id"
    t.index ["slug"], name: "index_articles_on_slug", unique: true
    t.index ["status"], name: "index_articles_on_status"
    t.index ["views"], name: "index_articles_on_views"
  end

  create_table "assignment_policies", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", limit: 255, null: false
    t.text "description"
    t.integer "assignment_order", default: 0, null: false
    t.integer "conversation_priority", default: 0, null: false
    t.integer "fair_distribution_limit", default: 100, null: false
    t.integer "fair_distribution_window", default: 3600, null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "sticky_contact", default: false, null: false
    t.boolean "require_online", default: true, null: false
    t.index ["account_id", "name"], name: "index_assignment_policies_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_assignment_policies_on_account_id"
    t.index ["enabled"], name: "index_assignment_policies_on_enabled"
  end

  create_table "attachments", id: :serial, force: :cascade do |t|
    t.integer "file_type", default: 0
    t.string "external_url"
    t.float "coordinates_lat", default: 0.0
    t.float "coordinates_long", default: 0.0
    t.integer "message_id", null: false
    t.integer "account_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "fallback_title"
    t.string "extension"
    t.jsonb "meta", default: {}
    t.index ["account_id"], name: "index_attachments_on_account_id"
    t.index ["message_id"], name: "index_attachments_on_message_id"
  end

  create_table "audits", force: :cascade do |t|
    t.bigint "auditable_id"
    t.string "auditable_type"
    t.bigint "associated_id"
    t.string "associated_type"
    t.bigint "user_id"
    t.string "user_type"
    t.string "username"
    t.string "action"
    t.jsonb "audited_changes"
    t.integer "version", default: 0
    t.string "comment"
    t.string "remote_address"
    t.string "request_uuid"
    t.datetime "created_at", precision: nil
    t.index ["associated_type", "associated_id"], name: "associated_index"
    t.index ["auditable_type", "auditable_id", "version"], name: "auditable_index"
    t.index ["created_at"], name: "index_audits_on_created_at"
    t.index ["request_uuid"], name: "index_audits_on_request_uuid"
    t.index ["user_id", "user_type"], name: "user_index"
  end

  create_table "automation_rule_firings", force: :cascade do |t|
    t.bigint "automation_rule_id", null: false
    t.bigint "conversation_id", null: false
    t.string "dedupe_key", null: false
    t.datetime "created_at", null: false
    t.index ["automation_rule_id", "conversation_id", "dedupe_key"], name: "index_automation_rule_firings_unique", unique: true
    t.index ["automation_rule_id"], name: "index_automation_rule_firings_on_automation_rule_id"
    t.index ["conversation_id"], name: "index_automation_rule_firings_on_conversation_id"
  end

  create_table "automation_rules", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.text "description"
    t.string "event_name", null: false
    t.jsonb "conditions", default: "{}", null: false
    t.jsonb "actions", default: "{}", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "active", default: true, null: false
    t.index ["account_id"], name: "index_automation_rules_on_account_id"
  end

  create_table "broadcast_recipients", force: :cascade do |t|
    t.bigint "broadcast_id", null: false
    t.bigint "contact_id", null: false
    t.bigint "conversation_id"
    t.integer "status", default: 0, null: false
    t.string "error"
    t.datetime "sent_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["broadcast_id", "status"], name: "index_broadcast_recipients_on_broadcast_id_and_status"
    t.index ["broadcast_id"], name: "index_broadcast_recipients_on_broadcast_id"
    t.index ["contact_id"], name: "index_broadcast_recipients_on_contact_id"
  end

  create_table "broadcasts", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "inbox_id"
    t.string "name", null: false
    t.string "mode", default: "waha", null: false
    t.integer "status", default: 0, null: false
    t.jsonb "message", default: {}
    t.jsonb "audience", default: {}
    t.jsonb "throttle", default: {}
    t.datetime "scheduled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_broadcasts_on_account_id"
    t.index ["inbox_id"], name: "index_broadcasts_on_inbox_id"
  end

  create_table "calls", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "inbox_id", null: false
    t.bigint "conversation_id", null: false
    t.bigint "contact_id", null: false
    t.bigint "message_id"
    t.bigint "accepted_by_agent_id"
    t.string "provider_call_id", null: false
    t.integer "provider", default: 0, null: false
    t.integer "direction", null: false
    t.string "status", default: "ringing", null: false
    t.datetime "started_at"
    t.integer "duration_seconds"
    t.string "end_reason"
    t.jsonb "meta", default: {}
    t.text "transcript"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "contact_id"], name: "index_calls_on_account_id_and_contact_id"
    t.index ["account_id", "conversation_id"], name: "index_calls_on_account_id_and_conversation_id"
    t.index ["message_id"], name: "index_calls_on_message_id"
    t.index ["provider", "provider_call_id"], name: "index_calls_on_provider_and_provider_call_id", unique: true
  end

  create_table "campaigns", force: :cascade do |t|
    t.integer "display_id", null: false
    t.string "title", null: false
    t.text "description"
    t.text "message", null: false
    t.integer "sender_id"
    t.boolean "enabled", default: true
    t.bigint "account_id", null: false
    t.bigint "inbox_id", null: false
    t.jsonb "trigger_rules", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "campaign_type", default: 0, null: false
    t.integer "campaign_status", default: 0, null: false
    t.jsonb "audience", default: []
    t.datetime "scheduled_at", precision: nil
    t.boolean "trigger_only_during_business_hours", default: false
    t.jsonb "template_params"
    t.index ["account_id"], name: "index_campaigns_on_account_id"
    t.index ["campaign_status"], name: "index_campaigns_on_campaign_status"
    t.index ["campaign_type"], name: "index_campaigns_on_campaign_type"
    t.index ["inbox_id"], name: "index_campaigns_on_inbox_id"
    t.index ["scheduled_at"], name: "index_campaigns_on_scheduled_at"
  end

  create_table "canned_responses", id: :serial, force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "short_code"
    t.text "content"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "captain_assistant_responses", force: :cascade do |t|
    t.string "question", null: false
    t.text "answer", null: false
    t.vector "embedding", limit: 1536
    t.bigint "assistant_id", null: false
    t.bigint "documentable_id"
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "status", default: 1, null: false
    t.string "documentable_type"
    t.boolean "edited", default: false, null: false
    t.index ["account_id"], name: "index_captain_assistant_responses_on_account_id"
    t.index ["assistant_id"], name: "index_captain_assistant_responses_on_assistant_id"
    t.index ["documentable_id", "documentable_type"], name: "idx_cap_asst_resp_on_documentable"
    t.index ["embedding"], name: "vector_idx_knowledge_entries_embedding", using: :ivfflat
    t.index ["status"], name: "index_captain_assistant_responses_on_status"
  end

  create_table "captain_assistants", force: :cascade do |t|
    t.string "name", null: false
    t.bigint "account_id", null: false
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "config", default: {}, null: false
    t.jsonb "response_guidelines", default: []
    t.jsonb "guardrails", default: []
    t.index ["account_id"], name: "index_captain_assistants_on_account_id"
  end

  create_table "captain_custom_tools", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "slug", null: false
    t.string "title", null: false
    t.text "description"
    t.string "http_method", default: "GET", null: false
    t.text "endpoint_url", null: false
    t.text "request_template"
    t.text "response_template"
    t.string "auth_type", default: "none"
    t.jsonb "auth_config", default: {}
    t.jsonb "param_schema", default: []
    t.boolean "enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "slug"], name: "index_captain_custom_tools_on_account_id_and_slug", unique: true
    t.index ["account_id"], name: "index_captain_custom_tools_on_account_id"
  end

  create_table "captain_documents", force: :cascade do |t|
    t.string "name"
    t.string "external_link", null: false
    t.text "content"
    t.bigint "assistant_id", null: false
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "status", default: 0, null: false
    t.jsonb "metadata", default: {}
    t.integer "sync_status"
    t.datetime "last_synced_at"
    t.datetime "last_sync_attempted_at"
    t.index ["account_id", "sync_status"], name: "index_captain_documents_on_account_id_and_sync_status"
    t.index ["account_id"], name: "index_captain_documents_on_account_id"
    t.index ["assistant_id", "external_link"], name: "index_captain_documents_on_assistant_id_and_external_link", unique: true
    t.index ["assistant_id"], name: "index_captain_documents_on_assistant_id"
    t.index ["status"], name: "index_captain_documents_on_status"
  end

  create_table "captain_inboxes", force: :cascade do |t|
    t.bigint "captain_assistant_id", null: false
    t.bigint "inbox_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["captain_assistant_id", "inbox_id"], name: "index_captain_inboxes_on_captain_assistant_id_and_inbox_id", unique: true
    t.index ["captain_assistant_id"], name: "index_captain_inboxes_on_captain_assistant_id"
    t.index ["inbox_id"], name: "index_captain_inboxes_on_inbox_id"
  end

  create_table "captain_scenarios", force: :cascade do |t|
    t.string "title"
    t.text "description"
    t.text "instruction"
    t.jsonb "tools", default: []
    t.boolean "enabled", default: true, null: false
    t.bigint "assistant_id", null: false
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_captain_scenarios_on_account_id"
    t.index ["assistant_id", "enabled"], name: "index_captain_scenarios_on_assistant_id_and_enabled"
    t.index ["assistant_id"], name: "index_captain_scenarios_on_assistant_id"
    t.index ["enabled"], name: "index_captain_scenarios_on_enabled"
  end

  create_table "categories", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "portal_id", null: false
    t.string "name"
    t.text "description"
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "locale", default: "en"
    t.string "slug", null: false
    t.bigint "parent_category_id"
    t.bigint "associated_category_id"
    t.string "icon", default: ""
    t.index ["associated_category_id"], name: "index_categories_on_associated_category_id"
    t.index ["locale", "account_id"], name: "index_categories_on_locale_and_account_id"
    t.index ["locale"], name: "index_categories_on_locale"
    t.index ["parent_category_id"], name: "index_categories_on_parent_category_id"
    t.index ["slug", "locale", "portal_id"], name: "index_categories_on_slug_and_locale_and_portal_id", unique: true
  end

  create_table "channel_api", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "webhook_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "identifier"
    t.string "hmac_token"
    t.boolean "hmac_mandatory", default: false
    t.jsonb "additional_attributes", default: {}
    t.string "secret"
    t.index ["hmac_token"], name: "index_channel_api_on_hmac_token", unique: true
    t.index ["identifier"], name: "index_channel_api_on_identifier", unique: true
  end

  create_table "channel_email", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "email", null: false
    t.string "forward_to_email", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "imap_enabled", default: false
    t.string "imap_address", default: ""
    t.integer "imap_port", default: 0
    t.string "imap_login", default: ""
    t.string "imap_password", default: ""
    t.boolean "imap_enable_ssl", default: true
    t.boolean "smtp_enabled", default: false
    t.string "smtp_address", default: ""
    t.integer "smtp_port", default: 0
    t.string "smtp_login", default: ""
    t.string "smtp_password", default: ""
    t.string "smtp_domain", default: ""
    t.boolean "smtp_enable_starttls_auto", default: true
    t.string "smtp_authentication", default: "login"
    t.string "smtp_openssl_verify_mode", default: "none"
    t.boolean "smtp_enable_ssl_tls", default: false
    t.jsonb "provider_config", default: {}
    t.string "provider"
    t.string "imap_authentication", default: "plain"
    t.boolean "verified_for_sending", default: false, null: false
    t.index ["email"], name: "index_channel_email_on_email", unique: true
    t.index ["forward_to_email"], name: "index_channel_email_on_forward_to_email", unique: true
  end

  create_table "channel_facebook_pages", id: :serial, force: :cascade do |t|
    t.string "page_id", null: false
    t.string "user_access_token", null: false
    t.string "page_access_token", null: false
    t.integer "account_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "instagram_id"
    t.index ["page_id", "account_id"], name: "index_channel_facebook_pages_on_page_id_and_account_id", unique: true
    t.index ["page_id"], name: "index_channel_facebook_pages_on_page_id"
  end

  create_table "channel_instagram", force: :cascade do |t|
    t.string "access_token", null: false
    t.datetime "expires_at", null: false
    t.integer "account_id", null: false
    t.string "instagram_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["instagram_id"], name: "index_channel_instagram_on_instagram_id", unique: true
  end

  create_table "channel_line", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "line_channel_id", null: false
    t.string "line_channel_secret", null: false
    t.string "line_channel_token", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["line_channel_id"], name: "index_channel_line_on_line_channel_id", unique: true
  end

  create_table "channel_sms", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "phone_number", null: false
    t.string "provider", default: "default"
    t.jsonb "provider_config", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["phone_number"], name: "index_channel_sms_on_phone_number", unique: true
  end

  create_table "channel_telegram", force: :cascade do |t|
    t.string "bot_name"
    t.integer "account_id", null: false
    t.string "bot_token", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bot_token"], name: "index_channel_telegram_on_bot_token", unique: true
  end

  create_table "channel_tiktok", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "business_id", null: false
    t.string "access_token", null: false
    t.datetime "expires_at", null: false
    t.string "refresh_token", null: false
    t.datetime "refresh_token_expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["business_id"], name: "index_channel_tiktok_on_business_id", unique: true
  end

  create_table "channel_twilio_sms", force: :cascade do |t|
    t.string "phone_number"
    t.string "auth_token", null: false
    t.string "account_sid", null: false
    t.integer "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "medium", default: 0
    t.string "messaging_service_sid"
    t.string "api_key_sid"
    t.jsonb "content_templates", default: {}
    t.datetime "content_templates_last_updated"
    t.boolean "voice_enabled", default: false, null: false
    t.string "twiml_app_sid"
    t.string "api_key_secret"
    t.index ["account_sid", "phone_number"], name: "index_channel_twilio_sms_on_account_sid_and_phone_number", unique: true
    t.index ["messaging_service_sid"], name: "index_channel_twilio_sms_on_messaging_service_sid", unique: true
    t.index ["phone_number"], name: "index_channel_twilio_sms_on_phone_number", unique: true
  end

  create_table "channel_twitter_profiles", force: :cascade do |t|
    t.string "profile_id", null: false
    t.string "twitter_access_token", null: false
    t.string "twitter_access_token_secret", null: false
    t.integer "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "tweets_enabled", default: true
    t.index ["account_id", "profile_id"], name: "index_channel_twitter_profiles_on_account_id_and_profile_id", unique: true
  end

  create_table "channel_web_widgets", id: :serial, force: :cascade do |t|
    t.string "website_url"
    t.integer "account_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "website_token"
    t.string "widget_color", default: "#1f93ff"
    t.string "welcome_title"
    t.string "welcome_tagline"
    t.integer "feature_flags", default: 7, null: false
    t.integer "reply_time", default: 0
    t.string "hmac_token"
    t.boolean "pre_chat_form_enabled", default: false
    t.jsonb "pre_chat_form_options", default: {}
    t.boolean "hmac_mandatory", default: false
    t.boolean "continuity_via_email", default: true, null: false
    t.text "allowed_domains", default: ""
    t.index ["hmac_token"], name: "index_channel_web_widgets_on_hmac_token", unique: true
    t.index ["website_token"], name: "index_channel_web_widgets_on_website_token", unique: true
  end

  create_table "channel_whatsapp", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "phone_number", null: false
    t.string "provider", default: "default"
    t.jsonb "provider_config", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "message_templates", default: {}
    t.datetime "message_templates_last_updated", precision: nil
    t.index ["phone_number"], name: "index_channel_whatsapp_on_phone_number", unique: true
  end

  create_table "chatflow_edges", force: :cascade do |t|
    t.bigint "chatflow_id", null: false
    t.bigint "account_id", null: false
    t.bigint "source_node_id", null: false
    t.bigint "target_node_id", null: false
    t.string "source_handle", limit: 255, default: "default", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_chatflow_edges_on_account_id"
    t.index ["chatflow_id"], name: "index_chatflow_edges_on_chatflow_id"
    t.index ["source_node_id", "source_handle"], name: "idx_chatflow_edges_unique_handle", unique: true
    t.index ["source_node_id"], name: "idx_chatflow_edges_on_source_node"
    t.index ["target_node_id"], name: "idx_chatflow_edges_on_target_node"
  end

  create_table "chatflow_executions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "chatflow_id", null: false
    t.bigint "conversation_id", null: false
    t.bigint "current_node_id"
    t.integer "status", default: 0, null: false
    t.jsonb "context", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_chatflow_executions_on_account_id"
    t.index ["chatflow_id"], name: "index_chatflow_executions_on_chatflow_id"
    t.index ["conversation_id"], name: "idx_chatflow_exec_one_live_per_conversation", unique: true, where: "(status < 2)"
    t.index ["conversation_id"], name: "index_chatflow_executions_on_conversation_id"
  end

  create_table "chatflow_nodes", force: :cascade do |t|
    t.bigint "chatflow_id", null: false
    t.bigint "account_id", null: false
    t.integer "kind", default: 0, null: false
    t.string "name", limit: 255
    t.float "position_x", default: 0.0, null: false
    t.float "position_y", default: 0.0, null: false
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_chatflow_nodes_on_account_id"
    t.index ["chatflow_id"], name: "index_chatflow_nodes_on_chatflow_id"
  end

  create_table "chatflows", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "inbox_id"
    t.string "name", limit: 255, null: false
    t.text "description"
    t.integer "status", default: 0, null: false
    t.integer "trigger_type", default: 0, null: false
    t.jsonb "trigger_config", default: {}, null: false
    t.bigint "start_node_id"
    t.bigint "display_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "color", default: "#5FB89F", null: false
    t.boolean "test_mode", default: false, null: false
    t.string "test_phone"
    t.index ["account_id", "display_id"], name: "index_chatflows_on_account_id_and_display_id", unique: true, where: "(display_id IS NOT NULL)"
    t.index ["account_id", "status"], name: "index_chatflows_on_account_id_and_status"
    t.index ["account_id"], name: "index_chatflows_on_account_id"
    t.index ["inbox_id"], name: "index_chatflows_on_inbox_id"
  end

  create_table "companies", force: :cascade do |t|
    t.string "name", null: false
    t.string "domain"
    t.text "description"
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "contacts_count"
    t.jsonb "additional_attributes", default: {}
    t.jsonb "custom_attributes", default: {}
    t.datetime "last_activity_at", precision: nil
    t.index ["account_id", "domain"], name: "index_companies_on_account_and_domain", unique: true, where: "(domain IS NOT NULL)"
    t.index ["account_id"], name: "index_companies_on_account_id"
    t.index ["name", "account_id"], name: "index_companies_on_name_and_account_id"
  end

  create_table "contact_inboxes", force: :cascade do |t|
    t.bigint "contact_id"
    t.bigint "inbox_id"
    t.text "source_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "hmac_verified", default: false
    t.string "pubsub_token"
    t.index ["contact_id"], name: "index_contact_inboxes_on_contact_id"
    t.index ["inbox_id", "source_id"], name: "index_contact_inboxes_on_inbox_id_and_source_id", unique: true
    t.index ["inbox_id"], name: "index_contact_inboxes_on_inbox_id"
    t.index ["pubsub_token"], name: "index_contact_inboxes_on_pubsub_token", unique: true
    t.index ["source_id"], name: "index_contact_inboxes_on_source_id"
  end

  create_table "contacts", id: :serial, force: :cascade do |t|
    t.string "name", default: ""
    t.string "email"
    t.string "phone_number"
    t.integer "account_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.jsonb "additional_attributes", default: {}
    t.string "identifier"
    t.jsonb "custom_attributes", default: {}
    t.datetime "last_activity_at", precision: nil
    t.integer "contact_type", default: 0
    t.string "middle_name", default: ""
    t.string "last_name", default: ""
    t.string "location", default: ""
    t.string "country_code", default: ""
    t.boolean "blocked", default: false, null: false
    t.bigint "company_id"
    t.index "lower((email)::text), account_id", name: "index_contacts_on_lower_email_account_id"
    t.index ["account_id", "contact_type"], name: "index_contacts_on_account_id_and_contact_type"
    t.index ["account_id", "email", "phone_number", "identifier"], name: "index_contacts_on_nonempty_fields", where: "(((email)::text <> ''::text) OR ((phone_number)::text <> ''::text) OR ((identifier)::text <> ''::text))"
    t.index ["account_id", "last_activity_at"], name: "index_contacts_on_account_id_and_last_activity_at", order: { last_activity_at: "DESC NULLS LAST" }
    t.index ["account_id"], name: "index_contacts_on_account_id"
    t.index ["account_id"], name: "index_resolved_contact_account_id", where: "(((email)::text <> ''::text) OR ((phone_number)::text <> ''::text) OR ((identifier)::text <> ''::text))"
    t.index ["blocked"], name: "index_contacts_on_blocked"
    t.index ["company_id"], name: "index_contacts_on_company_id"
    t.index ["email", "account_id"], name: "uniq_email_per_account_contact", unique: true
    t.index ["identifier", "account_id"], name: "uniq_identifier_per_account_contact", unique: true
    t.index ["name", "email", "phone_number", "identifier"], name: "index_contacts_on_name_email_phone_number_identifier", opclass: :gin_trgm_ops, using: :gin
    t.index ["phone_number", "account_id"], name: "index_contacts_on_phone_number_and_account_id"
  end

  create_table "conversation_participants", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_conversation_participants_on_account_id"
    t.index ["conversation_id"], name: "index_conversation_participants_on_conversation_id"
    t.index ["user_id", "conversation_id"], name: "index_conversation_participants_on_user_id_and_conversation_id", unique: true
    t.index ["user_id"], name: "index_conversation_participants_on_user_id"
  end

  create_table "conversations", id: :serial, force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "inbox_id", null: false
    t.integer "status", default: 0, null: false
    t.integer "assignee_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.bigint "contact_id"
    t.integer "display_id", null: false
    t.datetime "contact_last_seen_at", precision: nil
    t.datetime "agent_last_seen_at", precision: nil
    t.jsonb "additional_attributes", default: {}
    t.bigint "contact_inbox_id"
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.string "identifier"
    t.datetime "last_activity_at", precision: nil, default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.bigint "team_id"
    t.bigint "campaign_id"
    t.datetime "snoozed_until", precision: nil
    t.jsonb "custom_attributes", default: {}
    t.datetime "assignee_last_seen_at", precision: nil
    t.datetime "first_reply_created_at", precision: nil
    t.integer "priority"
    t.bigint "sla_policy_id"
    t.datetime "waiting_since"
    t.text "cached_label_list"
    t.bigint "assignee_agent_bot_id"
    t.bigint "ai_assistant_id"
    t.string "ai_mode"
    t.datetime "pinned_at"
    t.boolean "is_group", default: false, null: false
    t.boolean "awaiting_reply", default: false, null: false
    t.boolean "is_status_broadcast", default: false, null: false
    t.boolean "is_team", default: false, null: false
    t.index ["account_id", "display_id"], name: "index_conversations_on_account_id_and_display_id", unique: true
    t.index ["account_id", "id"], name: "index_conversations_on_id_and_account_id"
    t.index ["account_id", "inbox_id", "status", "assignee_id"], name: "conv_acid_inbid_stat_asgnid_idx"
    t.index ["account_id", "is_group"], name: "index_conversations_on_account_id_and_is_group"
    t.index ["account_id", "is_status_broadcast"], name: "index_conversations_on_account_id_and_is_status_broadcast"
    t.index ["account_id", "is_team"], name: "index_conversations_on_account_id_and_is_team"
    t.index ["account_id"], name: "index_conversations_on_account_id"
    t.index ["ai_assistant_id"], name: "index_conversations_on_ai_assistant_id"
    t.index ["ai_mode"], name: "index_conversations_on_ai_mode"
    t.index ["assignee_id", "account_id"], name: "index_conversations_on_assignee_id_and_account_id"
    t.index ["campaign_id"], name: "index_conversations_on_campaign_id"
    t.index ["contact_id"], name: "index_conversations_on_contact_id"
    t.index ["contact_inbox_id"], name: "index_conversations_on_contact_inbox_id"
    t.index ["first_reply_created_at"], name: "index_conversations_on_first_reply_created_at"
    t.index ["identifier", "account_id"], name: "index_conversations_on_identifier_and_account_id"
    t.index ["inbox_id"], name: "index_conversations_on_inbox_id"
    t.index ["pinned_at"], name: "index_conversations_on_pinned_at"
    t.index ["priority"], name: "index_conversations_on_priority"
    t.index ["status", "account_id"], name: "index_conversations_on_status_and_account_id"
    t.index ["status", "priority"], name: "index_conversations_on_status_and_priority"
    t.index ["team_id"], name: "index_conversations_on_team_id"
    t.index ["uuid"], name: "index_conversations_on_uuid", unique: true
    t.index ["waiting_since"], name: "index_conversations_on_waiting_since"
  end

  create_table "copilot_messages", force: :cascade do |t|
    t.bigint "copilot_thread_id", null: false
    t.bigint "account_id", null: false
    t.jsonb "message", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "message_type", default: 0
    t.index ["account_id"], name: "index_copilot_messages_on_account_id"
    t.index ["copilot_thread_id"], name: "index_copilot_messages_on_copilot_thread_id"
  end

  create_table "copilot_threads", force: :cascade do |t|
    t.string "title", null: false
    t.bigint "user_id", null: false
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "assistant_id"
    t.index ["account_id"], name: "index_copilot_threads_on_account_id"
    t.index ["assistant_id"], name: "index_copilot_threads_on_assistant_id"
    t.index ["user_id"], name: "index_copilot_threads_on_user_id"
  end

  create_table "csat_survey_responses", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "conversation_id", null: false
    t.bigint "message_id", null: false
    t.integer "rating", null: false
    t.text "feedback_message"
    t.bigint "contact_id", null: false
    t.bigint "assigned_agent_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "csat_review_notes"
    t.datetime "review_notes_updated_at"
    t.bigint "review_notes_updated_by_id"
    t.index ["account_id"], name: "index_csat_survey_responses_on_account_id"
    t.index ["assigned_agent_id"], name: "index_csat_survey_responses_on_assigned_agent_id"
    t.index ["contact_id"], name: "index_csat_survey_responses_on_contact_id"
    t.index ["conversation_id"], name: "index_csat_survey_responses_on_conversation_id"
    t.index ["message_id"], name: "index_csat_survey_responses_on_message_id", unique: true
    t.index ["review_notes_updated_by_id"], name: "index_csat_survey_responses_on_review_notes_updated_by_id"
  end

  create_table "custom_attribute_definitions", force: :cascade do |t|
    t.string "attribute_display_name"
    t.string "attribute_key"
    t.integer "attribute_display_type", default: 0
    t.integer "default_value"
    t.integer "attribute_model", default: 0
    t.bigint "account_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "attribute_description"
    t.jsonb "attribute_values", default: []
    t.string "regex_pattern"
    t.string "regex_cue"
    t.index ["account_id"], name: "index_custom_attribute_definitions_on_account_id"
    t.index ["attribute_key", "attribute_model", "account_id"], name: "attribute_key_model_index", unique: true
  end

  create_table "custom_filters", force: :cascade do |t|
    t.string "name", null: false
    t.integer "filter_type", default: 0, null: false
    t.jsonb "query", default: "{}", null: false
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_custom_filters_on_account_id"
    t.index ["user_id"], name: "index_custom_filters_on_user_id"
  end

  create_table "custom_roles", force: :cascade do |t|
    t.string "name"
    t.string "description"
    t.bigint "account_id", null: false
    t.text "permissions", default: [], array: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_custom_roles_on_account_id"
  end

  create_table "dashboard_apps", force: :cascade do |t|
    t.string "title", null: false
    t.jsonb "content", default: []
    t.bigint "account_id", null: false
    t.bigint "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_dashboard_apps_on_account_id"
    t.index ["user_id"], name: "index_dashboard_apps_on_user_id"
  end

  create_table "data_imports", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "data_type", null: false
    t.integer "status", default: 0, null: false
    t.text "processing_errors"
    t.integer "total_records"
    t.integer "processed_records"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_data_imports_on_account_id"
  end

  create_table "email_templates", force: :cascade do |t|
    t.string "name", null: false
    t.text "body", null: false
    t.integer "account_id"
    t.integer "template_type", default: 1
    t.integer "locale", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name", "account_id"], name: "index_email_templates_on_name_and_account_id", unique: true
  end

  create_table "folders", force: :cascade do |t|
    t.integer "account_id", null: false
    t.integer "category_id", null: false
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "funnel_agents", force: :cascade do |t|
    t.bigint "funnel_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["funnel_id", "user_id"], name: "index_funnel_agents_on_funnel_id_and_user_id", unique: true
    t.index ["funnel_id"], name: "index_funnel_agents_on_funnel_id"
    t.index ["user_id"], name: "index_funnel_agents_on_user_id"
  end

  create_table "funnel_custom_fields", force: :cascade do |t|
    t.bigint "funnel_id", null: false
    t.string "name", null: false
    t.integer "field_type", default: 0, null: false
    t.jsonb "options", default: {}, null: false
    t.integer "position", default: 0, null: false
    t.boolean "required", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["funnel_id"], name: "index_funnel_custom_fields_on_funnel_id"
  end

  create_table "funnel_inboxes", force: :cascade do |t|
    t.bigint "funnel_id", null: false
    t.bigint "inbox_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["funnel_id", "inbox_id"], name: "index_funnel_inboxes_on_funnel_id_and_inbox_id", unique: true
    t.index ["funnel_id"], name: "index_funnel_inboxes_on_funnel_id"
    t.index ["inbox_id"], name: "index_funnel_inboxes_on_inbox_id"
  end

  create_table "funnel_stages", force: :cascade do |t|
    t.bigint "funnel_id", null: false
    t.string "name", limit: 120, null: false
    t.text "description"
    t.string "color", default: "#64748B", null: false
    t.integer "position", default: 0, null: false
    t.integer "status_type", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "wip_limit"
    t.index ["funnel_id", "position"], name: "index_funnel_stages_on_funnel_id_and_position"
    t.index ["funnel_id", "status_type"], name: "index_funnel_stages_on_funnel_id_and_status_type"
    t.index ["funnel_id"], name: "index_funnel_stages_on_funnel_id"
  end

  create_table "funnels", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", limit: 120, null: false
    t.text "description"
    t.integer "position", default: 0, null: false
    t.jsonb "automation_settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], name: "index_funnels_on_account_id_and_name"
    t.index ["account_id", "position"], name: "index_funnels_on_account_id_and_position"
    t.index ["account_id"], name: "index_funnels_on_account_id"
  end

  create_table "inbox_assignment_policies", force: :cascade do |t|
    t.bigint "inbox_id", null: false
    t.bigint "assignment_policy_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["assignment_policy_id"], name: "index_inbox_assignment_policies_on_assignment_policy_id"
    t.index ["inbox_id"], name: "index_inbox_assignment_policies_on_inbox_id", unique: true
  end

  create_table "inbox_capacity_limits", force: :cascade do |t|
    t.bigint "agent_capacity_policy_id", null: false
    t.bigint "inbox_id", null: false
    t.integer "conversation_limit", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_capacity_policy_id", "inbox_id"], name: "idx_on_agent_capacity_policy_id_inbox_id_71c7ec4caf", unique: true
    t.index ["agent_capacity_policy_id"], name: "index_inbox_capacity_limits_on_agent_capacity_policy_id"
    t.index ["inbox_id"], name: "index_inbox_capacity_limits_on_inbox_id"
  end

  create_table "inbox_groups", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", limit: 60, null: false
    t.string "kind"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "kind"], name: "index_inbox_groups_on_account_id_and_kind", unique: true, where: "(kind IS NOT NULL)"
    t.index ["account_id"], name: "index_inbox_groups_on_account_id"
  end

  create_table "inbox_members", id: :serial, force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "inbox_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "assignment_capacity"
    t.index ["inbox_id", "user_id"], name: "index_inbox_members_on_inbox_id_and_user_id", unique: true
    t.index ["inbox_id"], name: "index_inbox_members_on_inbox_id"
  end

  create_table "inboxes", id: :serial, force: :cascade do |t|
    t.integer "channel_id", null: false
    t.integer "account_id", null: false
    t.string "name", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "channel_type"
    t.boolean "enable_auto_assignment", default: true
    t.boolean "greeting_enabled", default: false
    t.string "greeting_message"
    t.string "email_address"
    t.boolean "working_hours_enabled", default: false
    t.string "out_of_office_message"
    t.string "timezone", default: "UTC"
    t.boolean "enable_email_collect", default: true
    t.boolean "csat_survey_enabled", default: false
    t.boolean "allow_messages_after_resolved", default: true
    t.jsonb "auto_assignment_config", default: {}
    t.boolean "lock_to_single_conversation", default: false, null: false
    t.bigint "portal_id"
    t.integer "sender_name_type", default: 0, null: false
    t.string "business_name"
    t.jsonb "csat_config", default: {}, null: false
    t.bigint "ai_assistant_id"
    t.string "ai_mode", default: "off"
    t.bigint "inbox_group_id"
    t.index ["account_id"], name: "index_inboxes_on_account_id"
    t.index ["ai_assistant_id"], name: "index_inboxes_on_ai_assistant_id"
    t.index ["channel_id", "channel_type"], name: "index_inboxes_on_channel_id_and_channel_type"
    t.index ["inbox_group_id"], name: "index_inboxes_on_inbox_group_id"
    t.index ["portal_id"], name: "index_inboxes_on_portal_id"
  end

  create_table "installation_configs", force: :cascade do |t|
    t.string "name", null: false
    t.jsonb "serialized_value", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "locked", default: true, null: false
    t.index ["name", "created_at"], name: "index_installation_configs_on_name_and_created_at", unique: true
    t.index ["name"], name: "index_installation_configs_on_name", unique: true
  end

  create_table "integrations_hooks", force: :cascade do |t|
    t.integer "status", default: 1
    t.integer "inbox_id"
    t.integer "account_id"
    t.string "app_id"
    t.integer "hook_type", default: 0
    t.string "reference_id"
    t.string "access_token"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "settings", default: {}
  end

  create_table "kanban_api_tokens", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "created_by_user_id"
    t.string "name", limit: 120, null: false
    t.string "token_prefix", limit: 32, null: false
    t.string "token_digest", limit: 128, null: false
    t.jsonb "scopes", default: [], null: false
    t.datetime "expires_at"
    t.datetime "last_used_at"
    t.string "last_used_ip", limit: 64
    t.datetime "revoked_at"
    t.bigint "revoked_by_user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "revoked_at"], name: "index_kanban_api_tokens_on_account_id_and_revoked_at"
    t.index ["account_id"], name: "index_kanban_api_tokens_on_account_id"
    t.index ["created_by_user_id"], name: "index_kanban_api_tokens_on_created_by_user_id"
    t.index ["token_digest"], name: "index_kanban_api_tokens_on_token_digest", unique: true
    t.index ["token_prefix"], name: "index_kanban_api_tokens_on_token_prefix"
  end

  create_table "kanban_automations", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "funnel_id"
    t.string "name", limit: 120, null: false
    t.text "description"
    t.string "event_name", limit: 64, null: false
    t.jsonb "conditions", default: {}, null: false
    t.jsonb "actions", default: [], null: false
    t.boolean "active", default: true, null: false
    t.integer "run_count", default: 0, null: false
    t.datetime "last_run_at"
    t.datetime "last_error_at"
    t.string "last_error_message", limit: 500
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "event_name", "active"], name: "idx_on_account_id_event_name_active_9ba5ed85e8"
    t.index ["account_id"], name: "index_kanban_automations_on_account_id"
    t.index ["funnel_id", "event_name", "active"], name: "idx_on_funnel_id_event_name_active_b9b429950d"
    t.index ["funnel_id"], name: "index_kanban_automations_on_funnel_id"
  end

  create_table "kanban_task_activities", force: :cascade do |t|
    t.bigint "kanban_task_id", null: false
    t.bigint "user_id"
    t.string "action", null: false
    t.text "summary", null: false
    t.jsonb "data", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["kanban_task_id", "created_at"], name: "idx_kanban_activities_timeline"
    t.index ["kanban_task_id"], name: "index_kanban_task_activities_on_kanban_task_id"
    t.index ["user_id"], name: "index_kanban_task_activities_on_user_id"
  end

  create_table "kanban_task_assignees", force: :cascade do |t|
    t.bigint "kanban_task_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["kanban_task_id", "user_id"], name: "idx_kt_assignees_unique", unique: true
    t.index ["kanban_task_id"], name: "idx_kanban_task_assignees_on_task"
    t.index ["user_id"], name: "index_kanban_task_assignees_on_user_id"
  end

  create_table "kanban_task_contacts", force: :cascade do |t|
    t.bigint "kanban_task_id", null: false
    t.bigint "contact_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["contact_id"], name: "index_kanban_task_contacts_on_contact_id"
    t.index ["kanban_task_id", "contact_id"], name: "idx_kt_contacts_unique", unique: true
    t.index ["kanban_task_id"], name: "idx_kt_contact_on_task"
  end

  create_table "kanban_task_conversations", force: :cascade do |t|
    t.bigint "kanban_task_id", null: false
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id"], name: "index_kanban_task_conversations_on_conversation_id"
    t.index ["kanban_task_id", "conversation_id"], name: "idx_kt_conversations_unique", unique: true
    t.index ["kanban_task_id"], name: "idx_kt_conv_on_task"
  end

  create_table "kanban_task_custom_values", force: :cascade do |t|
    t.bigint "kanban_task_id", null: false
    t.bigint "funnel_custom_field_id", null: false
    t.text "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["funnel_custom_field_id"], name: "idx_custom_values_on_field_id"
    t.index ["kanban_task_id", "funnel_custom_field_id"], name: "idx_custom_values_unique_per_task_field", unique: true
    t.index ["kanban_task_id"], name: "index_kanban_task_custom_values_on_kanban_task_id"
  end

  create_table "kanban_task_labels", force: :cascade do |t|
    t.bigint "kanban_task_id", null: false
    t.bigint "label_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["kanban_task_id", "label_id"], name: "idx_kt_labels_unique", unique: true
    t.index ["kanban_task_id"], name: "idx_kanban_task_labels_on_task"
    t.index ["label_id"], name: "index_kanban_task_labels_on_label_id"
  end

  create_table "kanban_task_time_entries", force: :cascade do |t|
    t.bigint "kanban_task_id", null: false
    t.bigint "user_id", null: false
    t.datetime "started_at", null: false
    t.datetime "ended_at"
    t.integer "duration_seconds"
    t.string "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["kanban_task_id", "ended_at"], name: "idx_kanban_time_entries_open"
    t.index ["kanban_task_id"], name: "index_kanban_task_time_entries_on_kanban_task_id"
    t.index ["user_id"], name: "index_kanban_task_time_entries_on_user_id"
  end

  create_table "kanban_tasks", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "funnel_id", null: false
    t.bigint "funnel_stage_id", null: false
    t.string "title", limit: 255, null: false
    t.text "description"
    t.integer "priority", default: 0, null: false
    t.integer "position", default: 0, null: false
    t.datetime "start_date"
    t.datetime "due_date"
    t.bigint "display_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "parent_task_id"
    t.integer "estimate_minutes"
    t.datetime "completed_at"
    t.index ["account_id", "display_id"], name: "index_kanban_tasks_on_account_id_and_display_id", unique: true, where: "(display_id IS NOT NULL)"
    t.index ["account_id", "funnel_id"], name: "index_kanban_tasks_on_account_id_and_funnel_id"
    t.index ["account_id"], name: "index_kanban_tasks_on_account_id"
    t.index ["completed_at"], name: "index_kanban_tasks_on_completed_at"
    t.index ["due_date"], name: "index_kanban_tasks_on_due_date"
    t.index ["funnel_id"], name: "index_kanban_tasks_on_funnel_id"
    t.index ["funnel_stage_id", "position"], name: "index_kanban_tasks_on_funnel_stage_id_and_position"
    t.index ["funnel_stage_id"], name: "index_kanban_tasks_on_funnel_stage_id"
    t.index ["parent_task_id"], name: "index_kanban_tasks_on_parent_task_id"
  end

  create_table "kanban_webhook_subscriptions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "created_by_user_id"
    t.string "name", limit: 120, null: false
    t.string "url", limit: 2048, null: false
    t.jsonb "events", default: [], null: false
    t.string "secret", limit: 128, null: false
    t.boolean "active", default: true, null: false
    t.integer "delivery_count", default: 0, null: false
    t.integer "failure_count", default: 0, null: false
    t.datetime "last_delivered_at"
    t.datetime "last_failed_at"
    t.string "last_error_message", limit: 500
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "active"], name: "index_kanban_webhook_subscriptions_on_account_id_and_active"
    t.index ["account_id"], name: "index_kanban_webhook_subscriptions_on_account_id"
    t.index ["created_by_user_id"], name: "index_kanban_webhook_subscriptions_on_created_by_user_id"
  end

  create_table "labels", force: :cascade do |t|
    t.string "title"
    t.text "description"
    t.string "color", default: "#1f93ff", null: false
    t.boolean "show_on_sidebar"
    t.bigint "account_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "closes_conversation", default: false, null: false
    t.index ["account_id"], name: "index_labels_on_account_id"
    t.index ["title", "account_id"], name: "index_labels_on_title_and_account_id", unique: true
  end

  create_table "leaves", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.date "start_date", null: false
    t.date "end_date", null: false
    t.integer "leave_type", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.text "reason"
    t.bigint "approved_by_id"
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"], name: "index_leaves_on_account_id_and_status"
    t.index ["account_id"], name: "index_leaves_on_account_id"
    t.index ["approved_by_id"], name: "index_leaves_on_approved_by_id"
    t.index ["user_id"], name: "index_leaves_on_user_id"
  end

  create_table "macros", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.integer "visibility", default: 0
    t.bigint "created_by_id"
    t.bigint "updated_by_id"
    t.jsonb "actions", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_macros_on_account_id"
  end

  create_table "mentions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "conversation_id", null: false
    t.bigint "account_id", null: false
    t.datetime "mentioned_at", precision: nil, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_mentions_on_account_id"
    t.index ["conversation_id"], name: "index_mentions_on_conversation_id"
    t.index ["user_id", "conversation_id"], name: "index_mentions_on_user_id_and_conversation_id", unique: true
    t.index ["user_id"], name: "index_mentions_on_user_id"
  end

  create_table "messages", id: :serial, force: :cascade do |t|
    t.text "content"
    t.integer "account_id", null: false
    t.integer "inbox_id", null: false
    t.integer "conversation_id", null: false
    t.integer "message_type", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "private", default: false, null: false
    t.integer "status", default: 0
    t.text "source_id"
    t.integer "content_type", default: 0, null: false
    t.json "content_attributes", default: {}
    t.string "sender_type"
    t.bigint "sender_id"
    t.jsonb "external_source_ids", default: {}
    t.jsonb "additional_attributes", default: {}
    t.text "processed_message_content"
    t.jsonb "sentiment", default: {}
    t.index "((additional_attributes -> 'campaign_id'::text))", name: "index_messages_on_additional_attributes_campaign_id", using: :gin
    t.index ["account_id", "content_type", "created_at"], name: "idx_messages_account_content_created"
    t.index ["account_id", "created_at", "message_type"], name: "index_messages_on_account_created_type"
    t.index ["account_id", "inbox_id"], name: "index_messages_on_account_id_and_inbox_id"
    t.index ["account_id"], name: "index_messages_on_account_id"
    t.index ["content"], name: "index_messages_on_content", opclass: :gin_trgm_ops, using: :gin
    t.index ["conversation_id", "account_id", "message_type", "created_at"], name: "index_messages_on_conversation_account_type_created"
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["created_at"], name: "index_messages_on_created_at"
    t.index ["inbox_id"], name: "index_messages_on_inbox_id"
    t.index ["sender_type", "sender_id"], name: "index_messages_on_sender_type_and_sender_id"
    t.index ["source_id"], name: "index_messages_on_source_id"
  end

  create_table "notes", force: :cascade do |t|
    t.text "content", null: false
    t.bigint "account_id", null: false
    t.bigint "contact_id", null: false
    t.bigint "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_notes_on_account_id"
    t.index ["contact_id"], name: "index_notes_on_contact_id"
    t.index ["user_id"], name: "index_notes_on_user_id"
  end

  create_table "notification_settings", force: :cascade do |t|
    t.integer "account_id"
    t.integer "user_id"
    t.integer "email_flags", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "push_flags", default: 0, null: false
    t.index ["account_id", "user_id"], name: "by_account_user", unique: true
  end

  create_table "notification_subscriptions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "subscription_type", null: false
    t.jsonb "subscription_attributes", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "identifier"
    t.index ["identifier"], name: "index_notification_subscriptions_on_identifier", unique: true
    t.index ["user_id"], name: "index_notification_subscriptions_on_user_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.integer "notification_type", null: false
    t.string "primary_actor_type", null: false
    t.bigint "primary_actor_id", null: false
    t.string "secondary_actor_type"
    t.bigint "secondary_actor_id"
    t.datetime "read_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "snoozed_until"
    t.datetime "last_activity_at", default: -> { "CURRENT_TIMESTAMP" }
    t.jsonb "meta", default: {}
    t.index ["account_id"], name: "index_notifications_on_account_id"
    t.index ["last_activity_at"], name: "index_notifications_on_last_activity_at"
    t.index ["primary_actor_type", "primary_actor_id"], name: "uniq_primary_actor_per_account_notifications"
    t.index ["secondary_actor_type", "secondary_actor_id"], name: "uniq_secondary_actor_per_account_notifications"
    t.index ["user_id", "account_id", "snoozed_until", "read_at"], name: "idx_notifications_performance"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "platform_app_permissibles", force: :cascade do |t|
    t.bigint "platform_app_id", null: false
    t.string "permissible_type", null: false
    t.bigint "permissible_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["permissible_type", "permissible_id"], name: "index_platform_app_permissibles_on_permissibles"
    t.index ["platform_app_id", "permissible_id", "permissible_type"], name: "unique_permissibles_index", unique: true
    t.index ["platform_app_id"], name: "index_platform_app_permissibles_on_platform_app_id"
  end

  create_table "platform_apps", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "platform_banners", force: :cascade do |t|
    t.text "banner_message", null: false
    t.integer "banner_type", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "portals", force: :cascade do |t|
    t.integer "account_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.string "custom_domain"
    t.string "color"
    t.string "homepage_link"
    t.string "page_title"
    t.text "header_text"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "config", default: {"allowed_locales" => ["en"]}
    t.boolean "archived", default: false
    t.bigint "channel_web_widget_id"
    t.jsonb "ssl_settings", default: {}, null: false
    t.index ["channel_web_widget_id"], name: "index_portals_on_channel_web_widget_id"
    t.index ["custom_domain"], name: "index_portals_on_custom_domain", unique: true
    t.index ["slug"], name: "index_portals_on_slug", unique: true
  end

  create_table "portals_members", id: false, force: :cascade do |t|
    t.bigint "portal_id", null: false
    t.bigint "user_id", null: false
    t.index ["portal_id", "user_id"], name: "index_portals_members_on_portal_id_and_user_id", unique: true
    t.index ["portal_id"], name: "index_portals_members_on_portal_id"
    t.index ["user_id"], name: "index_portals_members_on_user_id"
  end

  create_table "related_categories", force: :cascade do |t|
    t.bigint "category_id"
    t.bigint "related_category_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id", "related_category_id"], name: "index_related_categories_on_category_id_and_related_category_id", unique: true
    t.index ["related_category_id", "category_id"], name: "index_related_categories_on_related_category_id_and_category_id", unique: true
  end

  create_table "reporting_events", force: :cascade do |t|
    t.string "name"
    t.float "value"
    t.integer "account_id"
    t.integer "inbox_id"
    t.integer "user_id"
    t.integer "conversation_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.float "value_in_business_hours"
    t.datetime "event_start_time", precision: nil
    t.datetime "event_end_time", precision: nil
    t.index ["account_id", "name", "created_at"], name: "reporting_events__account_id__name__created_at"
    t.index ["account_id", "name", "inbox_id", "created_at"], name: "index_reporting_events_for_response_distribution"
    t.index ["account_id"], name: "index_reporting_events_on_account_id"
    t.index ["conversation_id"], name: "index_reporting_events_on_conversation_id"
    t.index ["created_at"], name: "index_reporting_events_on_created_at"
    t.index ["inbox_id"], name: "index_reporting_events_on_inbox_id"
    t.index ["name"], name: "index_reporting_events_on_name"
    t.index ["user_id"], name: "index_reporting_events_on_user_id"
  end

  create_table "reporting_events_rollups", force: :cascade do |t|
    t.integer "account_id", null: false
    t.date "date", null: false
    t.string "dimension_type", null: false
    t.bigint "dimension_id", null: false
    t.string "metric", null: false
    t.bigint "count", default: 0, null: false
    t.float "sum_value", default: 0.0, null: false
    t.float "sum_value_business_hours", default: 0.0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "date", "dimension_type", "dimension_id", "metric"], name: "index_rollup_unique_key", unique: true
    t.index ["account_id", "dimension_type", "date"], name: "index_rollup_summary"
    t.index ["account_id", "metric", "date"], name: "index_rollup_timeseries"
  end

  create_table "sale_records", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "contact_id"
    t.bigint "user_id", null: false
    t.decimal "amount", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "recorded_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "category", default: "sales", null: false
    t.string "order_number"
    t.datetime "paid_at"
    t.index ["account_id", "user_id", "category", "recorded_at"], name: "index_sale_records_on_account_user_category_recorded"
    t.index ["account_id", "user_id", "recorded_at"], name: "index_sale_records_on_account_id_and_user_id_and_recorded_at"
    t.index ["account_id"], name: "index_sale_records_on_account_id"
    t.index ["contact_id"], name: "index_sale_records_on_contact_id"
    t.index ["user_id"], name: "index_sale_records_on_user_id"
  end

  create_table "sales_goals", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.integer "period", default: 0, null: false
    t.decimal "target_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name", default: "Vendas", null: false
    t.integer "unit", default: 0, null: false
    t.string "category", default: "sales", null: false
    t.index ["account_id", "category"], name: "index_sales_goals_on_account_id_and_category"
    t.index ["account_id", "user_id"], name: "index_sales_goals_on_account_id_and_user_id"
    t.index ["account_id"], name: "index_sales_goals_on_account_id"
    t.index ["user_id"], name: "index_sales_goals_on_user_id"
  end

  create_table "sla_events", force: :cascade do |t|
    t.bigint "applied_sla_id", null: false
    t.bigint "conversation_id", null: false
    t.bigint "account_id", null: false
    t.bigint "sla_policy_id", null: false
    t.bigint "inbox_id", null: false
    t.integer "event_type"
    t.jsonb "meta", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_sla_events_on_account_id"
    t.index ["applied_sla_id"], name: "index_sla_events_on_applied_sla_id"
    t.index ["conversation_id"], name: "index_sla_events_on_conversation_id"
    t.index ["inbox_id"], name: "index_sla_events_on_inbox_id"
    t.index ["sla_policy_id"], name: "index_sla_events_on_sla_policy_id"
  end

  create_table "sla_policies", force: :cascade do |t|
    t.string "name", null: false
    t.float "first_response_time_threshold"
    t.float "next_response_time_threshold"
    t.boolean "only_during_business_hours", default: false
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "description"
    t.float "resolution_time_threshold"
    t.index ["account_id"], name: "index_sla_policies_on_account_id"
  end

  create_table "taggings", id: :serial, force: :cascade do |t|
    t.integer "tag_id"
    t.string "taggable_type"
    t.integer "taggable_id"
    t.string "tagger_type"
    t.integer "tagger_id"
    t.string "context", limit: 128
    t.datetime "created_at", precision: nil
    t.index ["context"], name: "index_taggings_on_context"
    t.index ["tag_id", "taggable_id", "taggable_type", "context", "tagger_id", "tagger_type"], name: "taggings_idx", unique: true
    t.index ["tag_id"], name: "index_taggings_on_tag_id"
    t.index ["taggable_id", "taggable_type", "context"], name: "index_taggings_on_taggable_id_and_taggable_type_and_context"
    t.index ["taggable_id", "taggable_type", "tagger_id", "context"], name: "taggings_idy"
    t.index ["taggable_id"], name: "index_taggings_on_taggable_id"
    t.index ["taggable_type"], name: "index_taggings_on_taggable_type"
    t.index ["tagger_id", "tagger_type"], name: "index_taggings_on_tagger_id_and_tagger_type"
    t.index ["tagger_id"], name: "index_taggings_on_tagger_id"
  end

  create_table "tags", id: :serial, force: :cascade do |t|
    t.string "name"
    t.integer "taggings_count", default: 0
    t.index "lower((name)::text) gin_trgm_ops", name: "tags_name_trgm_idx", using: :gin
    t.index ["name"], name: "index_tags_on_name", unique: true
  end

  create_table "task_activities", force: :cascade do |t|
    t.bigint "task_id", null: false
    t.bigint "user_id"
    t.string "action", limit: 64, null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["task_id", "created_at"], name: "index_task_activities_on_task_id_and_created_at"
    t.index ["task_id"], name: "index_task_activities_on_task_id"
    t.index ["user_id"], name: "index_task_activities_on_user_id"
  end

  create_table "task_assignees", force: :cascade do |t|
    t.bigint "task_id", null: false
    t.bigint "user_id", null: false
    t.datetime "notified_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["task_id", "user_id"], name: "index_task_assignees_on_task_id_and_user_id", unique: true
    t.index ["task_id"], name: "index_task_assignees_on_task_id"
    t.index ["user_id"], name: "index_task_assignees_on_user_id"
  end

  create_table "task_comments", force: :cascade do |t|
    t.bigint "task_id", null: false
    t.bigint "user_id", null: false
    t.jsonb "body", default: {}, null: false
    t.datetime "edited_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["task_id"], name: "index_task_comments_on_task_id"
    t.index ["user_id"], name: "index_task_comments_on_user_id"
  end

  create_table "task_views", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id"
    t.string "name", limit: 120, null: false
    t.jsonb "filters", default: {}, null: false
    t.integer "position", default: 0, null: false
    t.boolean "is_default", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "position"], name: "index_task_views_on_account_id_and_position"
    t.index ["account_id", "user_id"], name: "index_task_views_on_account_id_and_user_id"
    t.index ["account_id"], name: "index_task_views_on_account_id"
    t.index ["user_id"], name: "index_task_views_on_user_id"
  end

  create_table "tasks", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "created_by_user_id"
    t.bigint "display_id"
    t.string "title", limit: 255, null: false
    t.jsonb "description", default: {}, null: false
    t.integer "status", default: 0, null: false
    t.integer "urgency", default: 0, null: false
    t.datetime "due_date"
    t.datetime "completed_at"
    t.boolean "notify_assignees", default: true, null: false
    t.jsonb "custom_attributes", default: {}, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "recurrence_rule", default: {}, null: false
    t.bigint "recurrence_parent_id"
    t.datetime "next_occurrence_at"
    t.index ["account_id", "display_id"], name: "index_tasks_on_account_id_and_display_id", unique: true, where: "(display_id IS NOT NULL)"
    t.index ["account_id", "due_date"], name: "index_tasks_on_account_id_and_due_date"
    t.index ["account_id", "status"], name: "index_tasks_on_account_id_and_status"
    t.index ["account_id", "urgency"], name: "index_tasks_on_account_id_and_urgency"
    t.index ["account_id"], name: "index_tasks_on_account_id"
    t.index ["created_by_user_id"], name: "index_tasks_on_created_by_user_id"
    t.index ["next_occurrence_at"], name: "index_tasks_on_next_occurrence_at"
    t.index ["recurrence_parent_id"], name: "index_tasks_on_recurrence_parent_id"
  end

  create_table "team_chat_channels", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "created_by_user_id"
    t.string "name", limit: 80, null: false
    t.string "slug", limit: 80, null: false
    t.text "description"
    t.integer "kind", default: 0, null: false
    t.integer "position", default: 0, null: false
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "position"], name: "index_team_chat_channels_on_account_id_and_position"
    t.index ["account_id", "slug"], name: "index_team_chat_channels_on_account_id_and_slug", unique: true
    t.index ["account_id"], name: "index_team_chat_channels_on_account_id"
    t.index ["created_by_user_id"], name: "index_team_chat_channels_on_created_by_user_id"
  end

  create_table "team_chat_messages", force: :cascade do |t|
    t.bigint "channel_id", null: false
    t.bigint "user_id", null: false
    t.text "content", null: false
    t.datetime "edited_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["channel_id", "created_at"], name: "index_team_chat_messages_on_channel_id_and_created_at"
    t.index ["channel_id"], name: "index_team_chat_messages_on_channel_id"
    t.index ["user_id"], name: "index_team_chat_messages_on_user_id"
  end

  create_table "team_members", force: :cascade do |t|
    t.bigint "team_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["team_id", "user_id"], name: "index_team_members_on_team_id_and_user_id", unique: true
    t.index ["team_id"], name: "index_team_members_on_team_id"
    t.index ["user_id"], name: "index_team_members_on_user_id"
  end

  create_table "teams", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.boolean "allow_auto_assign", default: true
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_teams_on_account_id"
    t.index ["name", "account_id"], name: "index_teams_on_name_and_account_id", unique: true
  end

  create_table "univercart_processed_events", id: :string, force: :cascade do |t|
    t.string "event_type", null: false
    t.string "subscription_id"
    t.datetime "processed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "univercart_subscriptions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "external_user_id", null: false
    t.string "email", null: false
    t.string "name", null: false
    t.string "document"
    t.string "phone"
    t.string "role", null: false
    t.string "status", default: "pending", null: false
    t.string "product_slug"
    t.string "plan_id"
    t.string "billing_period"
    t.integer "amount_cents"
    t.string "currency", default: "BRL"
    t.datetime "valid_until"
    t.datetime "cancelled_at"
    t.string "cancel_reason"
    t.integer "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_univercart_subscriptions_on_email"
    t.index ["external_user_id"], name: "index_univercart_subscriptions_on_external_user_id", unique: true
    t.index ["status", "valid_until"], name: "index_univercart_subscriptions_on_status_and_valid_until"
    t.index ["user_id"], name: "index_univercart_subscriptions_on_user_id"
  end

  create_table "users", id: :serial, force: :cascade do |t|
    t.string "provider", default: "email", null: false
    t.string "uid", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at", precision: nil
    t.datetime "remember_created_at", precision: nil
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at", precision: nil
    t.datetime "last_sign_in_at", precision: nil
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.string "confirmation_token"
    t.datetime "confirmed_at", precision: nil
    t.datetime "confirmation_sent_at", precision: nil
    t.string "unconfirmed_email"
    t.string "name", null: false
    t.string "display_name"
    t.string "email"
    t.json "tokens"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "pubsub_token"
    t.integer "availability", default: 0
    t.jsonb "ui_settings", default: {}
    t.jsonb "custom_attributes", default: {}
    t.string "type"
    t.text "message_signature"
    t.string "otp_secret"
    t.integer "consumed_timestep"
    t.boolean "otp_required_for_login", default: false
    t.text "otp_backup_codes"
    t.string "accepted_terms_version"
    t.string "accepted_privacy_version"
    t.datetime "accepted_at"
    t.datetime "scheduled_for_deletion_at"
    t.index ["accepted_terms_version"], name: "index_users_on_accepted_terms_version"
    t.index ["email"], name: "index_users_on_email"
    t.index ["otp_required_for_login"], name: "index_users_on_otp_required_for_login"
    t.index ["otp_secret"], name: "index_users_on_otp_secret", unique: true
    t.index ["pubsub_token"], name: "index_users_on_pubsub_token", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["scheduled_for_deletion_at"], name: "index_users_on_scheduled_for_deletion_at"
    t.index ["uid", "provider"], name: "index_users_on_uid_and_provider", unique: true
  end

  create_table "vertical_statuses", force: :cascade do |t|
    t.bigint "vertical_id", null: false
    t.string "title", null: false
    t.string "color", default: "#1f93ff", null: false
    t.text "description"
    t.boolean "closes_conversation", default: false, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["vertical_id"], name: "index_vertical_statuses_on_vertical_id"
  end

  create_table "verticals", force: :cascade do |t|
    t.string "key", null: false
    t.string "name", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_verticals_on_key", unique: true
  end

  create_table "webhooks", force: :cascade do |t|
    t.integer "account_id"
    t.integer "inbox_id"
    t.text "url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "webhook_type", default: 0
    t.jsonb "subscriptions", default: ["conversation_status_changed", "conversation_updated", "conversation_created", "contact_created", "contact_updated", "message_created", "message_updated", "webwidget_triggered"]
    t.string "name"
    t.string "secret"
    t.index ["account_id", "url"], name: "index_webhooks_on_account_id_and_url", unique: true
  end

  create_table "whatsapp_flows", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "inbox_id", null: false
    t.string "name", limit: 255, null: false
    t.string "category", default: "OTHER", null: false
    t.string "template_key"
    t.jsonb "flow_json", default: {}, null: false
    t.jsonb "field_mappings", default: {}, null: false
    t.string "meta_flow_id"
    t.string "status", default: "draft", null: false
    t.jsonb "validation_errors", default: [], null: false
    t.string "preview_url"
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_whatsapp_flows_on_account_id"
    t.index ["inbox_id"], name: "index_whatsapp_flows_on_inbox_id"
    t.index ["meta_flow_id"], name: "index_whatsapp_flows_on_meta_flow_id", unique: true, where: "(meta_flow_id IS NOT NULL)"
  end

  create_table "whatsapp_status_deliveries", force: :cascade do |t|
    t.bigint "whatsapp_status_post_id", null: false
    t.bigint "inbox_id"
    t.string "inbox_name", null: false
    t.integer "status", default: 0, null: false
    t.string "waha_message_id"
    t.text "error_message"
    t.datetime "sent_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["inbox_id"], name: "index_whatsapp_status_deliveries_on_inbox_id"
    t.index ["whatsapp_status_post_id"], name: "index_whatsapp_status_deliveries_on_whatsapp_status_post_id"
  end

  create_table "whatsapp_status_posts", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id"
    t.string "kind", default: "text", null: false
    t.text "body"
    t.string "background_color"
    t.integer "font", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.jsonb "inbox_ids", default: [], null: false
    t.datetime "scheduled_at"
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "recurrence", default: "none", null: false
    t.index ["account_id", "status", "scheduled_at"], name: "idx_on_account_id_status_scheduled_at_e293e01cb2"
    t.index ["account_id"], name: "index_whatsapp_status_posts_on_account_id"
    t.index ["user_id"], name: "index_whatsapp_status_posts_on_user_id"
  end

  create_table "whatsapp_status_templates", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "name", null: false
    t.text "body", null: false
    t.string "background_color"
    t.integer "font", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], name: "index_whatsapp_status_templates_on_account_id_and_name", unique: true
    t.index ["account_id"], name: "index_whatsapp_status_templates_on_account_id"
  end

  create_table "working_hours", force: :cascade do |t|
    t.bigint "inbox_id"
    t.bigint "account_id"
    t.integer "day_of_week", null: false
    t.boolean "closed_all_day", default: false
    t.integer "open_hour"
    t.integer "open_minutes"
    t.integer "close_hour"
    t.integer "close_minutes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "open_all_day", default: false
    t.index ["account_id"], name: "index_working_hours_on_account_id"
    t.index ["inbox_id"], name: "index_working_hours_on_inbox_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "ai_ab_comparisons", "accounts"
  add_foreign_key "ai_ab_comparisons", "ai_assistants"
  add_foreign_key "ai_ab_comparisons", "ai_invocations"
  add_foreign_key "ai_ab_comparisons", "ai_prompt_versions"
  add_foreign_key "ai_assistants", "accounts"
  add_foreign_key "ai_belezaki_connections", "accounts"
  add_foreign_key "ai_belezaki_connections", "ai_assistants"
  add_foreign_key "ai_calendar_appointment_services", "ai_calendar_appointments"
  add_foreign_key "ai_calendar_appointment_services", "ai_calendar_services"
  add_foreign_key "ai_calendar_appointments", "accounts"
  add_foreign_key "ai_calendar_appointments", "ai_assistants"
  add_foreign_key "ai_calendar_appointments", "ai_calendar_professionals"
  add_foreign_key "ai_calendar_appointments", "contacts"
  add_foreign_key "ai_calendar_appointments", "conversations"
  add_foreign_key "ai_calendar_connections", "accounts"
  add_foreign_key "ai_calendar_connections", "ai_assistants"
  add_foreign_key "ai_calendar_hours", "accounts"
  add_foreign_key "ai_calendar_hours", "ai_calendar_professionals"
  add_foreign_key "ai_calendar_professionals", "accounts"
  add_foreign_key "ai_calendar_professionals", "ai_assistants"
  add_foreign_key "ai_calendar_professionals", "ai_calendar_connections"
  add_foreign_key "ai_calendar_service_professionals", "ai_calendar_professionals"
  add_foreign_key "ai_calendar_service_professionals", "ai_calendar_services"
  add_foreign_key "ai_calendar_services", "accounts"
  add_foreign_key "ai_calendar_services", "ai_assistants"
  add_foreign_key "ai_calendar_settings", "accounts"
  add_foreign_key "ai_calendar_settings", "ai_assistants"
  add_foreign_key "ai_chat_messages", "accounts"
  add_foreign_key "ai_chat_messages", "ai_chat_threads"
  add_foreign_key "ai_chat_threads", "accounts"
  add_foreign_key "ai_chat_threads", "ai_assistants"
  add_foreign_key "ai_chat_threads", "users"
  add_foreign_key "ai_credit_ledger_entries", "accounts"
  add_foreign_key "ai_credit_ledger_entries", "ai_invocations"
  add_foreign_key "ai_custom_tools", "accounts"
  add_foreign_key "ai_custom_tools", "ai_assistants"
  add_foreign_key "ai_intents", "accounts"
  add_foreign_key "ai_intents", "ai_assistants"
  add_foreign_key "ai_invocations", "accounts"
  add_foreign_key "ai_invocations", "ai_assistants"
  add_foreign_key "ai_lead_opportunities", "accounts"
  add_foreign_key "ai_lead_opportunities", "ai_assistants"
  add_foreign_key "ai_manager_check_settings", "accounts"
  add_foreign_key "ai_manager_conversation_findings", "accounts"
  add_foreign_key "ai_manager_conversation_scans", "accounts"
  add_foreign_key "ai_manager_runs", "accounts"
  add_foreign_key "ai_manager_suggestions", "accounts"
  add_foreign_key "ai_manager_suggestions", "ai_assistants"
  add_foreign_key "ai_manager_suggestions", "ai_manager_runs"
  add_foreign_key "ai_manager_suggestions", "ai_prompt_versions", on_delete: :nullify
  add_foreign_key "ai_manager_suggestions", "ai_trainings", on_delete: :nullify
  add_foreign_key "ai_prompt_versions", "accounts"
  add_foreign_key "ai_prompt_versions", "ai_assistants"
  add_foreign_key "ai_response_feedbacks", "accounts"
  add_foreign_key "ai_response_feedbacks", "ai_assistants"
  add_foreign_key "ai_response_feedbacks", "ai_invocations"
  add_foreign_key "ai_response_histories", "accounts"
  add_foreign_key "ai_response_histories", "ai_assistants"
  add_foreign_key "ai_revenue_events", "accounts"
  add_foreign_key "ai_revenue_events", "ai_assistants"
  add_foreign_key "ai_trainings", "accounts"
  add_foreign_key "ai_trainings", "ai_assistants"
  add_foreign_key "automation_rule_firings", "automation_rules", on_delete: :cascade
  add_foreign_key "automation_rule_firings", "conversations", on_delete: :cascade
  add_foreign_key "broadcast_recipients", "broadcasts"
  add_foreign_key "broadcast_recipients", "contacts"
  add_foreign_key "broadcasts", "accounts"
  add_foreign_key "broadcasts", "inboxes"
  add_foreign_key "chatflow_edges", "accounts"
  add_foreign_key "chatflow_edges", "chatflow_nodes", column: "source_node_id", on_delete: :cascade
  add_foreign_key "chatflow_edges", "chatflow_nodes", column: "target_node_id", on_delete: :cascade
  add_foreign_key "chatflow_edges", "chatflows", on_delete: :cascade
  add_foreign_key "chatflow_executions", "accounts"
  add_foreign_key "chatflow_executions", "chatflows", on_delete: :cascade
  add_foreign_key "chatflow_executions", "conversations", on_delete: :cascade
  add_foreign_key "chatflow_nodes", "accounts"
  add_foreign_key "chatflow_nodes", "chatflows", on_delete: :cascade
  add_foreign_key "chatflows", "accounts"
  add_foreign_key "chatflows", "inboxes", on_delete: :cascade
  add_foreign_key "conversations", "ai_assistants"
  add_foreign_key "funnel_agents", "funnels", on_delete: :cascade
  add_foreign_key "funnel_agents", "users"
  add_foreign_key "funnel_custom_fields", "funnels", on_delete: :cascade
  add_foreign_key "funnel_inboxes", "funnels", on_delete: :cascade
  add_foreign_key "funnel_inboxes", "inboxes"
  add_foreign_key "funnel_stages", "funnels", on_delete: :cascade
  add_foreign_key "funnels", "accounts"
  add_foreign_key "inbox_groups", "accounts"
  add_foreign_key "inboxes", "ai_assistants"
  add_foreign_key "inboxes", "inbox_groups", on_delete: :nullify
  add_foreign_key "inboxes", "portals"
  add_foreign_key "kanban_api_tokens", "accounts"
  add_foreign_key "kanban_api_tokens", "users", column: "created_by_user_id"
  add_foreign_key "kanban_automations", "accounts"
  add_foreign_key "kanban_automations", "funnels"
  add_foreign_key "kanban_task_activities", "kanban_tasks", on_delete: :cascade
  add_foreign_key "kanban_task_activities", "users"
  add_foreign_key "kanban_task_assignees", "kanban_tasks", on_delete: :cascade
  add_foreign_key "kanban_task_assignees", "users"
  add_foreign_key "kanban_task_contacts", "contacts"
  add_foreign_key "kanban_task_contacts", "kanban_tasks", on_delete: :cascade
  add_foreign_key "kanban_task_conversations", "conversations"
  add_foreign_key "kanban_task_conversations", "kanban_tasks", on_delete: :cascade
  add_foreign_key "kanban_task_custom_values", "funnel_custom_fields", on_delete: :cascade
  add_foreign_key "kanban_task_custom_values", "kanban_tasks", on_delete: :cascade
  add_foreign_key "kanban_task_labels", "kanban_tasks", on_delete: :cascade
  add_foreign_key "kanban_task_labels", "labels"
  add_foreign_key "kanban_task_time_entries", "kanban_tasks", on_delete: :cascade
  add_foreign_key "kanban_task_time_entries", "users"
  add_foreign_key "kanban_tasks", "accounts"
  add_foreign_key "kanban_tasks", "funnel_stages", on_delete: :restrict
  add_foreign_key "kanban_tasks", "funnels", on_delete: :cascade
  add_foreign_key "kanban_tasks", "kanban_tasks", column: "parent_task_id", on_delete: :cascade
  add_foreign_key "kanban_webhook_subscriptions", "accounts"
  add_foreign_key "kanban_webhook_subscriptions", "users", column: "created_by_user_id"
  add_foreign_key "sale_records", "accounts"
  add_foreign_key "sale_records", "contacts"
  add_foreign_key "sale_records", "users"
  add_foreign_key "sales_goals", "accounts"
  add_foreign_key "sales_goals", "users"
  add_foreign_key "task_activities", "tasks"
  add_foreign_key "task_activities", "users"
  add_foreign_key "task_assignees", "tasks"
  add_foreign_key "task_assignees", "users"
  add_foreign_key "task_comments", "tasks"
  add_foreign_key "task_comments", "users"
  add_foreign_key "task_views", "accounts"
  add_foreign_key "task_views", "users"
  add_foreign_key "tasks", "accounts"
  add_foreign_key "tasks", "users", column: "created_by_user_id"
  add_foreign_key "team_chat_channels", "accounts"
  add_foreign_key "team_chat_channels", "users", column: "created_by_user_id"
  add_foreign_key "team_chat_messages", "team_chat_channels", column: "channel_id"
  add_foreign_key "team_chat_messages", "users"
  add_foreign_key "univercart_subscriptions", "users"
  add_foreign_key "vertical_statuses", "verticals"
  add_foreign_key "whatsapp_flows", "accounts"
  add_foreign_key "whatsapp_flows", "inboxes", on_delete: :cascade
  add_foreign_key "whatsapp_status_deliveries", "inboxes", on_delete: :nullify
  add_foreign_key "whatsapp_status_deliveries", "whatsapp_status_posts", on_delete: :cascade
  add_foreign_key "whatsapp_status_posts", "accounts", on_delete: :cascade
  add_foreign_key "whatsapp_status_posts", "users", on_delete: :nullify
  add_foreign_key "whatsapp_status_templates", "accounts", on_delete: :cascade
  create_trigger("accounts_after_insert_row_tr", :generated => true, :compatibility => 1).
      on("accounts").
      after(:insert).
      for_each(:row) do
    "execute format('create sequence IF NOT EXISTS conv_dpid_seq_%s', NEW.id);"
  end

  create_trigger("conversations_before_insert_row_tr", :generated => true, :compatibility => 1).
      on("conversations").
      before(:insert).
      for_each(:row) do
    "NEW.display_id := nextval('conv_dpid_seq_' || NEW.account_id);"
  end

  create_trigger("camp_dpid_before_insert", :generated => true, :compatibility => 1).
      on("accounts").
      name("camp_dpid_before_insert").
      after(:insert).
      for_each(:row) do
    "execute format('create sequence IF NOT EXISTS camp_dpid_seq_%s', NEW.id);"
  end

  create_trigger("campaigns_before_insert_row_tr", :generated => true, :compatibility => 1).
      on("campaigns").
      before(:insert).
      for_each(:row) do
    "NEW.display_id := nextval('camp_dpid_seq_' || NEW.account_id);"
  end

end

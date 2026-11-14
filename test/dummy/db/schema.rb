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

ActiveRecord::Schema[8.1].define(version: 2026_11_14_075121) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "cards", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.uuid "page_id", null: false
    t.integer "position", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["page_id", "position"], name: "index_cards_on_page_id_and_position"
    t.index ["page_id"], name: "index_cards_on_page_id"
  end

  create_table "folders", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.string "summary", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["workspace_id", "position"], name: "index_folders_on_workspace_id_and_position"
    t.index ["workspace_id"], name: "index_folders_on_workspace_id"
  end

  create_table "message_groups", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "message_root_id", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.string "summary", null: false
    t.datetime "updated_at", null: false
    t.index ["message_root_id", "position"], name: "index_message_groups_on_message_root_id_and_position"
    t.index ["message_root_id"], name: "index_message_groups_on_message_root_id"
  end

  create_table "message_roots", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "pages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "folder_id", null: false
    t.integer "position", default: 0, null: false
    t.string "summary", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["folder_id", "position"], name: "index_pages_on_folder_id_and_position"
    t.index ["folder_id"], name: "index_pages_on_folder_id"
  end

  create_table "recording_studio_access_constraints", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action", null: false
    t.string "allowed_audiences", default: [], null: false, array: true
    t.datetime "created_at", null: false
    t.index ["action"], name: "index_recording_studio_access_constraints_on_action"
  end

  create_table "recording_studio_access_invitations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "accepted_at"
    t.uuid "accepted_by_actor_id"
    t.string "accepted_by_actor_type"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "expires_at", null: false
    t.datetime "last_sent_at", null: false
    t.uuid "manager_actor_id", null: false
    t.string "manager_actor_type", null: false
    t.uuid "recording_id", null: false
    t.datetime "revoked_at"
    t.string "role", null: false
    t.string "token_digest", limit: 64, null: false
    t.datetime "updated_at", null: false
    t.index ["recording_id", "email"], name: "idx_rs_access_invitations_one_active", unique: true, where: "((accepted_at IS NULL) AND (revoked_at IS NULL))"
    t.index ["recording_id"], name: "index_recording_studio_access_invitations_on_recording_id"
    t.index ["token_digest"], name: "idx_rs_access_invitations_token_digest", unique: true
    t.check_constraint "accepted_at IS NULL OR revoked_at IS NULL", name: "access_invitations_not_accepted_and_revoked"
  end

  create_table "recording_studio_access_request_intents", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "expires_at", null: false
    t.datetime "fulfilled_at"
    t.uuid "otp_challenge_id", null: false
    t.uuid "recording_id", null: false
    t.string "role"
    t.string "submitted_name"
    t.uuid "user_id", null: false
    t.index ["recording_id"], name: "index_recording_studio_access_request_intents_on_recording_id"
    t.check_constraint "action IS NULL OR char_length(action::text) <= 120", name: "recording_studio_access_request_intents_action_length"
    t.check_constraint "char_length(email::text) <= 255", name: "recording_studio_access_request_intents_email_length"
    t.check_constraint "submitted_name IS NULL OR char_length(submitted_name::text) <= 120", name: "recording_studio_access_request_intents_name_length"
  end

  create_table "recording_studio_access_requests", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "access_recording_id"
    t.string "action"
    t.uuid "actor_id", null: false
    t.string "actor_type", null: false
    t.datetime "created_at", null: false
    t.jsonb "gate_metadata", default: {}, null: false
    t.text "message"
    t.text "review_note"
    t.string "role"
    t.string "status", default: "pending", null: false
    t.uuid "target_recording_id", null: false
    t.string "pending_key"
    t.index ["actor_type", "actor_id"], name: "index_recording_studio_access_requests_on_actor"
    t.index ["pending_key"], name: "index_recording_studio_access_requests_one_pending", unique: true, where: "(pending_key IS NOT NULL)"
    t.check_constraint "action IS NULL OR char_length(action::text) <= 120", name: "recording_studio_access_requests_action_length"
    t.check_constraint "message IS NULL OR char_length(message) <= 2000", name: "recording_studio_access_requests_message_length"
    t.check_constraint "review_note IS NULL OR char_length(review_note) <= 2000", name: "recording_studio_access_requests_note_length"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'approved'::character varying::text, 'denied'::character varying::text])", name: "recording_studio_access_requests_status"
  end

  create_table "recording_studio_access_rules", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action", null: false
    t.string "audience", null: false
    t.datetime "created_at", null: false
    t.index ["action"], name: "index_recording_studio_access_rules_on_action"
  end

  create_table "recording_studio_accesses", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "actor_id", null: false
    t.string "actor_type", null: false
    t.datetime "created_at", null: false
    t.uuid "depends_on_recording_id"
    t.string "role", default: "view", null: false
    t.index ["actor_type", "actor_id", "role"], name: "index_recording_studio_accesses_on_actor_and_role"
    t.index ["actor_type", "actor_id"], name: "index_recording_studio_accesses_on_actor"
    t.index ["depends_on_recording_id"], name: "index_recording_studio_accesses_on_depends_on_recording_id"
  end

  create_table "recording_studio_api_admin_apis", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "key", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_recording_studio_api_admin_apis_on_key", unique: true
  end

  create_table "recording_studio_api_api_access_tokens", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "api_credential_id", null: false
    t.string "token_digest", null: false
    t.string "token_prefix", null: false
    t.datetime "expires_at", null: false
    t.datetime "last_used_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["api_credential_id"], name: "idx_on_api_credential_id_89874cbf51"
    t.index ["expires_at"], name: "index_recording_studio_api_api_access_tokens_on_expires_at"
    t.index ["token_digest"], name: "index_recording_studio_api_api_access_tokens_on_token_digest", unique: true
  end

  create_table "recording_studio_api_api_clients", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "access_recording_id"
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "api_key", default: "public", null: false
    t.index ["access_recording_id"], name: "index_recording_studio_api_api_clients_on_access_recording_id", unique: true
    t.index ["api_key"], name: "index_recording_studio_api_api_clients_on_api_key"
  end

  create_table "recording_studio_api_api_credentials", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "api_client_id", null: false
    t.uuid "access_recording_id", null: false
    t.string "token_public_id", null: false
    t.string "token_digest", null: false
    t.string "token_prefix", null: false
    t.datetime "expires_at"
    t.datetime "last_used_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["access_recording_id"], name: "idx_on_access_recording_id_103368144f"
    t.index ["api_client_id"], name: "index_recording_studio_api_api_credentials_on_api_client_id"
    t.index ["api_client_id"], name: "index_recording_studio_api_credentials_on_active_client", unique: true, where: "(revoked_at IS NULL)"
    t.index ["token_digest"], name: "index_recording_studio_api_api_credentials_on_token_digest", unique: true
    t.index ["token_public_id"], name: "index_recording_studio_api_api_credentials_on_token_public_id", unique: true
  end

  create_table "recording_studio_api_api_daily_latency_histogram_buckets", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.date "metric_date", null: false
    t.string "route_name", null: false
    t.string "request_method", null: false
    t.integer "status_class", null: false
    t.integer "upper_bound_ms", null: false
    t.bigint "request_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "api_key", default: "public", null: false
    t.index ["api_key", "metric_date", "route_name", "request_method", "status_class", "upper_bound_ms"], name: "index_rs_api_daily_latency_histogram_on_dimensions", unique: true
    t.index ["metric_date"], name: "idx_on_metric_date_8723beba88"
  end

  create_table "recording_studio_api_api_daily_metrics", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.date "metric_date", null: false
    t.string "route_name", null: false
    t.string "controller_name"
    t.string "action_name"
    t.string "request_method", null: false
    t.integer "status_class", null: false
    t.bigint "request_count", default: 0, null: false
    t.bigint "rate_limited_count", default: 0, null: false
    t.bigint "client_error_count", default: 0, null: false
    t.bigint "server_error_count", default: 0, null: false
    t.bigint "duration_count", default: 0, null: false
    t.bigint "duration_sum_ms", default: 0, null: false
    t.integer "duration_max_ms", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "api_key", default: "public", null: false
    t.index ["api_key", "metric_date", "route_name", "request_method", "status_class"], name: "index_rs_api_daily_metrics_on_dimensions", unique: true
    t.index ["metric_date"], name: "index_recording_studio_api_api_daily_metrics_on_metric_date"
  end

  create_table "recording_studio_api_api_request_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "occurred_at", null: false
    t.string "request_id"
    t.string "request_method", null: false
    t.string "request_path", null: false
    t.string "route_name"
    t.string "controller_name"
    t.string "action_name"
    t.integer "status_code", null: false
    t.integer "duration_ms", null: false
    t.boolean "rate_limited", default: false, null: false
    t.uuid "api_client_id"
    t.uuid "api_credential_id"
    t.uuid "access_recording_id"
    t.uuid "root_recording_id"
    t.string "remote_ip"
    t.string "user_agent"
    t.string "error_class"
    t.string "error_message"
    t.jsonb "request_params", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "api_key", default: "public", null: false
    t.datetime "arrived_at", default: -> { "clock_timestamp()" }
    t.integer "latency_bucket_ms"
    t.index ["api_client_id", "occurred_at"], name: "index_rs_api_request_logs_on_client_and_time"
    t.index ["api_credential_id", "occurred_at"], name: "index_rs_api_request_logs_on_credential_and_time"
    t.index ["api_key", "occurred_at"], name: "index_rs_api_request_logs_on_api_and_time"
    t.index ["occurred_at"], name: "index_recording_studio_api_api_request_logs_on_occurred_at"
    t.index ["request_id"], name: "index_recording_studio_api_api_request_logs_on_request_id"
    t.index ["request_path"], name: "index_recording_studio_api_api_request_logs_on_request_path"
    t.index ["status_code"], name: "index_recording_studio_api_api_request_logs_on_status_code"
  end

  create_table "recording_studio_api_api_settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "key", null: false
    t.boolean "api_access_enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "runtime_overrides", default: {}, null: false
    t.index ["key"], name: "index_recording_studio_api_api_settings_on_key", unique: true
  end

  create_table "recording_studio_device_sessions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "actor_id", null: false
    t.string "actor_type", null: false
    t.datetime "created_at", null: false
    t.string "device_fingerprint", null: false
    t.string "device_name"
    t.datetime "last_active_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.uuid "root_recording_id", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.index ["actor_type", "actor_id", "device_fingerprint"], name: "index_rs_device_sessions_on_actor_and_fingerprint", unique: true
    t.index ["root_recording_id"], name: "index_rs_device_sessions_on_root_recording"
  end

  create_table "recording_studio_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action", null: false
    t.uuid "actor_id"
    t.string "actor_type"
    t.datetime "created_at", null: false
    t.string "idempotency_key"
    t.uuid "impersonator_id"
    t.string "impersonator_type"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "occurred_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.uuid "previous_recordable_id"
    t.string "previous_recordable_type"
    t.uuid "recordable_id", null: false
    t.string "recordable_type", null: false
    t.uuid "recording_id", null: false
    t.uuid "root_recording_id", null: false
    t.index ["impersonator_type", "impersonator_id", "occurred_at"], name: "index_rs_events_on_impersonator_and_occurred_at"
    t.index ["recording_id", "idempotency_key"], name: "index_recording_studio_events_on_recording_and_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["recording_id"], name: "index_recording_studio_events_on_recording_id"
    t.index ["root_recording_id", "occurred_at", "created_at", "id"], name: "index_rs_events_on_root_and_timeline", order: { occurred_at: :desc, created_at: :desc, id: :desc }
  end

  create_table "recording_studio_logs_aggregation_runs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "aggregation_name", null: false
    t.datetime "period_start", null: false
    t.string "status", null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["aggregation_name", "period_start"], name: "index_rs_logs_aggregation_runs_on_name_and_period", unique: true
  end

  create_table "recording_studio_logs_maintenance_runs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "task", null: false
    t.string "subject", null: false
    t.string "status", null: false
    t.text "details"
    t.datetime "finished_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["task", "subject", "finished_at"], name: "index_rs_logs_maintenance_runs_on_task_and_subject"
  end

  create_table "recording_studio_notifications_deliveries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "channel", null: false
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.text "error_message"
    t.jsonb "metadata", default: {}, null: false
    t.uuid "notification_id", null: false
    t.datetime "rollup_reserved_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["channel", "status"], name: "idx_rsn_deliveries_channel_status"
    t.index ["notification_id", "channel"], name: "idx_rsn_deliveries_notification_channel", unique: true
    t.index ["status", "rollup_reserved_at"], name: "idx_rsn_deliveries_rollup_reservation"
  end

  create_table "recording_studio_notifications_notifications", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "actor_id"
    t.string "actor_type"
    t.datetime "archived_at"
    t.text "body"
    t.datetime "cleared_at"
    t.datetime "created_at", null: false
    t.string "idempotency_key"
    t.jsonb "metadata", default: {}, null: false
    t.uuid "notifiable_id"
    t.string "notifiable_type"
    t.string "notification_type", null: false
    t.datetime "read_at"
    t.uuid "recipient_id", null: false
    t.string "recipient_type", null: false
    t.uuid "recording_id"
    t.uuid "root_recording_id"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.boolean "inbox", default: true, null: false
    t.index ["recipient_type", "recipient_id", "idempotency_key"], name: "idx_rsn_notifications_idempotency", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["recipient_type", "recipient_id", "notification_type"], name: "idx_rsn_notifications_recipient_type"
    t.index ["recording_id"], name: "idx_rsn_notifications_recording"
    t.index ["root_recording_id", "created_at"], name: "idx_rsn_notifications_root_created"
  end

  create_table "recording_studio_notifications_preferences", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "cadence"
    t.string "channel"
    t.datetime "created_at", null: false
    t.boolean "enabled"
    t.string "notification_type", null: false
    t.uuid "recipient_id", null: false
    t.string "recipient_type", null: false
    t.datetime "updated_at", null: false
    t.index ["notification_type", "channel"], name: "idx_rsn_preferences_type_channel"
    t.index ["recipient_type", "recipient_id", "notification_type", "channel"], name: "idx_rsn_preferences_channel", unique: true, where: "(channel IS NOT NULL)"
    t.index ["recipient_type", "recipient_id", "notification_type"], name: "idx_rsn_preferences_cadence", unique: true, where: "(channel IS NULL)"
    t.check_constraint "channel IS NOT NULL AND enabled IS NOT NULL AND cadence IS NULL OR channel IS NULL AND enabled IS NULL AND cadence IS NOT NULL", name: "chk_rsn_preferences_shape"
  end

  create_table "recording_studio_recordings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "parent_recording_id"
    t.uuid "recordable_id", null: false
    t.string "recordable_type", null: false
    t.uuid "root_recording_id"
    t.datetime "trashed_at"
    t.datetime "updated_at", null: false
    t.datetime "purge_at"
    t.index ["parent_recording_id"], name: "index_recording_studio_recordings_on_parent_recording_id"
    t.index ["purge_at"], name: "idx_rs_recordings_due_purge_at", where: "(trashed_at IS NOT NULL)"
    t.index ["recordable_id", "root_recording_id"], name: "idx_rs_recordings_root_access", where: "(((recordable_type)::text = 'RecordingStudio::Access'::text) AND (parent_recording_id IS NOT NULL) AND (trashed_at IS NULL))"
    t.index ["recordable_type", "recordable_id", "parent_recording_id", "trashed_at"], name: "index_recording_studio_recordings_on_recordable_parent_trashed"
    t.index ["recordable_type", "recordable_id"], name: "index_recording_studio_recordings_on_recordable"
    t.index ["root_recording_id"], name: "index_rs_recordings_on_root_recording"
  end

  create_table "recording_studio_root_switchable_selections", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "actor_id"
    t.string "actor_type"
    t.datetime "created_at", null: false
    t.string "device_browser"
    t.string "device_key", null: false
    t.string "device_label"
    t.string "device_platform"
    t.string "device_type"
    t.datetime "last_used_at", null: false
    t.uuid "root_recording_id", null: false
    t.string "scope_key", null: false
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.index ["actor_type", "actor_id", "device_key", "scope_key"], name: "idx_rs_root_switchable_actor_device_scope", unique: true, where: "(actor_id IS NOT NULL)"
    t.index ["device_key", "scope_key"], name: "idx_rs_root_switchable_anonymous_device_scope", unique: true, where: "(actor_id IS NULL)"
    t.index ["root_recording_id"], name: "idx_rs_root_switchable_root_recording"
  end

  create_table "recording_studio_user_identities", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "provider", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["provider", "uid"], name: "index_recording_studio_user_identities_on_provider_and_uid", unique: true
    t.index ["user_id", "provider"], name: "index_recording_studio_user_identities_on_user_id_and_provider", unique: true
    t.index ["user_id"], name: "index_recording_studio_user_identities_on_user_id"
  end

  create_table "recording_studio_user_otp_challenges", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "attempts_count", default: 0, null: false
    t.string "code_digest", null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.text "delivery_code_ciphertext"
    t.datetime "delivery_requested_at"
    t.datetime "expires_at", null: false
    t.string "purpose", null: false
    t.datetime "revoked_at"
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.datetime "verified_at"
    t.index ["expires_at"], name: "index_recording_studio_user_otp_challenges_on_expires_at"
    t.index ["user_id", "purpose"], name: "idx_on_user_id_purpose_2b7c2a59c4"
    t.index ["user_id", "purpose"], name: "index_rs_user_otp_challenges_open_purpose", unique: true, where: "((consumed_at IS NULL) AND (revoked_at IS NULL))"
    t.index ["user_id"], name: "index_recording_studio_user_otp_challenges_on_user_id"
  end

  create_table "recording_studio_user_people", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
  end

  create_table "recording_studio_user_profiles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.jsonb "additional_profile_attributes", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "first_name", null: false
    t.string "last_name"
    t.string "time_zone", default: "UTC"
    t.uuid "user_id", null: false
    t.index ["user_id"], name: "index_recording_studio_user_profiles_on_user_id"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "confirmation_sent_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "registered_with", default: "password", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "unconfirmed_email"
    t.datetime "updated_at", null: false
    t.index "lower((email)::text)", name: "index_users_on_lower_email", unique: true
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.check_constraint "registered_with::text = ANY (ARRAY['password'::character varying::text, 'otp'::character varying::text])", name: "users_registered_with_check"
  end

  create_table "workspaces", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  add_foreign_key "cards", "pages"
  add_foreign_key "folders", "workspaces"
  add_foreign_key "message_groups", "message_roots"
  add_foreign_key "pages", "folders"
  add_foreign_key "recording_studio_access_invitations", "recording_studio_recordings", column: "recording_id"
  add_foreign_key "recording_studio_api_api_access_tokens", "recording_studio_api_api_credentials", column: "api_credential_id"
  add_foreign_key "recording_studio_api_api_credentials", "recording_studio_api_api_clients", column: "api_client_id"
  add_foreign_key "recording_studio_device_sessions", "recording_studio_recordings", column: "root_recording_id"
  add_foreign_key "recording_studio_events", "recording_studio_recordings", column: "recording_id"
  add_foreign_key "recording_studio_events", "recording_studio_recordings", column: "root_recording_id"
  add_foreign_key "recording_studio_notifications_deliveries", "recording_studio_notifications_notifications", column: "notification_id"
  add_foreign_key "recording_studio_recordings", "recording_studio_recordings", column: "parent_recording_id"
  add_foreign_key "recording_studio_recordings", "recording_studio_recordings", column: "root_recording_id"
  add_foreign_key "recording_studio_root_switchable_selections", "recording_studio_recordings", column: "root_recording_id"
  add_foreign_key "recording_studio_user_identities", "users"
  add_foreign_key "recording_studio_user_otp_challenges", "users"
  add_foreign_key "recording_studio_user_profiles", "users"
end

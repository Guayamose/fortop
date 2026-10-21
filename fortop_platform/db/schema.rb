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

ActiveRecord::Schema[8.1].define(version: 2026_10_22_000300) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "brand_brief_documents", id: false, force: :cascade do |t|
    t.bigint "brand_brief_id", null: false
    t.bigint "brand_document_id", null: false
    t.index ["brand_brief_id", "brand_document_id"], name: "idx_on_brand_brief_id_brand_document_id_4f3d209f2a", unique: true
    t.index ["brand_document_id"], name: "index_brand_brief_documents_on_brand_document_id"
  end

  create_table "brand_briefs", force: :cascade do |t|
    t.bigint "brand_id", null: false
    t.integer "version", null: false
    t.text "content", null: false
    t.jsonb "context", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["brand_id", "version"], name: "index_brand_briefs_on_brand_id_and_version", unique: true
    t.index ["brand_id"], name: "index_brand_briefs_on_brand_id"
  end

  create_table "brand_document_links", id: false, force: :cascade do |t|
    t.bigint "brand_id", null: false
    t.bigint "brand_document_id", null: false
    t.index ["brand_document_id"], name: "index_brand_document_links_on_brand_document_id"
    t.index ["brand_id", "brand_document_id"], name: "index_brand_document_links_on_brand_id_and_brand_document_id", unique: true
  end

  create_table "brand_documents", force: :cascade do |t|
    t.bigint "brand_import_id", null: false
    t.text "extracted_text"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["brand_import_id"], name: "index_brand_documents_on_brand_import_id"
  end

  create_table "brand_imports", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "status", default: "queued", null: false
    t.text "input_fields"
    t.text "result"
    t.string "model"
    t.decimal "spent_usd", precision: 12, scale: 6, default: "0.0", null: false
    t.integer "request_count", default: 0, null: false
    t.jsonb "usage", default: {}, null: false
    t.text "error_message"
    t.boolean "retryable", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_brand_imports_on_user_id"
  end

  create_table "brands", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.string "website", null: false
    t.text "brief", null: false
    t.jsonb "markets", default: [], null: false
    t.jsonb "aliases", default: [], null: false
    t.text "known_competitors"
    t.jsonb "context_overrides", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_brands_on_user_id"
  end

  create_table "findings", force: :cascade do |t|
    t.bigint "scan_id", null: false
    t.string "title", null: false
    t.text "description", null: false
    t.string "severity", default: "medium", null: false
    t.string "category", null: false
    t.string "file_path"
    t.integer "line_number"
    t.text "evidence"
    t.text "recommendation"
    t.boolean "automatable", default: true, null: false
    t.string "status", default: "open", null: false
    t.string "issue_url"
    t.integer "issue_number"
    t.string "fingerprint", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "impact"
    t.text "verification"
    t.text "remediation_rationale"
    t.index ["scan_id", "fingerprint"], name: "index_findings_on_scan_id_and_fingerprint", unique: true
    t.index ["scan_id"], name: "index_findings_on_scan_id"
  end

  create_table "repositories", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "github_id", null: false
    t.string "full_name", null: false
    t.text "description"
    t.string "default_branch", default: "main", null: false
    t.string "html_url", null: false
    t.string "language"
    t.boolean "private", default: false, null: false
    t.datetime "connected_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "installation_id"
    t.index ["installation_id"], name: "index_repositories_on_installation_id"
    t.index ["user_id", "github_id"], name: "index_repositories_on_user_id_and_github_id", unique: true
    t.index ["user_id"], name: "index_repositories_on_user_id"
  end

  create_table "scan_events", force: :cascade do |t|
    t.bigint "scan_id", null: false
    t.string "kind", default: "status", null: false
    t.text "message", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["scan_id", "created_at"], name: "index_scan_events_on_scan_id_and_created_at"
    t.index ["scan_id"], name: "index_scan_events_on_scan_id"
  end

  create_table "scans", force: :cascade do |t|
    t.bigint "repository_id", null: false
    t.string "status", default: "queued", null: false
    t.integer "progress", default: 0, null: false
    t.text "summary"
    t.text "error_message"
    t.string "base_sha"
    t.string "branch_name"
    t.string "pull_request_url"
    t.integer "pull_request_number"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.jsonb "metadata", default: {}, null: false
    t.jsonb "validation_results", default: [], null: false
    t.jsonb "changed_files", default: [], null: false
    t.integer "agent_steps", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "publication_changes"
    t.string "control_action"
    t.text "execution_state"
    t.index ["repository_id", "created_at"], name: "index_scans_on_repository_id_and_created_at"
    t.index ["repository_id"], name: "index_scans_on_repository_id"
    t.index ["repository_id"], name: "one_active_scan_per_repository", unique: true, where: "((status)::text = ANY ((ARRAY['queued'::character varying, 'discovering'::character varying, 'analyzing'::character varying, 'remediating'::character varying, 'validating'::character varying, 'publishing'::character varying, 'paused'::character varying])::text[]))"
    t.check_constraint "progress >= 0 AND progress <= 100", name: "scan_progress_range"
  end

  create_table "users", force: :cascade do |t|
    t.bigint "github_id", null: false
    t.string "login", null: false
    t.string "name"
    t.string "email"
    t.string "avatar_url"
    t.text "github_token", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "github_refresh_token"
    t.datetime "github_token_expires_at"
    t.index ["github_id"], name: "index_users_on_github_id", unique: true
  end

  create_table "visibility_actions", force: :cascade do |t|
    t.bigint "visibility_study_id", null: false
    t.bigint "repository_id"
    t.bigint "scan_id"
    t.string "fingerprint", null: false
    t.string "title", null: false
    t.text "description", null: false
    t.string "kind", default: "editorial", null: false
    t.string "priority", default: "medium", null: false
    t.string "effort", default: "medium", null: false
    t.string "status", default: "planned", null: false
    t.jsonb "observation_ids", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["repository_id"], name: "index_visibility_actions_on_repository_id"
    t.index ["scan_id"], name: "index_visibility_actions_on_scan_id"
    t.index ["visibility_study_id", "fingerprint"], name: "unique_visibility_action", unique: true
    t.index ["visibility_study_id"], name: "index_visibility_actions_on_visibility_study_id"
  end

  create_table "visibility_calls", force: :cascade do |t|
    t.bigint "visibility_study_id", null: false
    t.string "task_key", null: false
    t.integer "attempt", default: 1, null: false
    t.string "status", default: "running", null: false
    t.string "model", null: false
    t.string "model_version"
    t.boolean "grounded", default: false, null: false
    t.text "response_text"
    t.jsonb "citations", default: [], null: false
    t.jsonb "search_queries", default: [], null: false
    t.text "search_entry_point"
    t.jsonb "usage", default: {}, null: false
    t.decimal "cost_usd", precision: 12, scale: 6, default: "0.0", null: false
    t.text "error_message"
    t.boolean "retryable", default: false, null: false
    t.datetime "observed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "input_prompt"
    t.text "system_instruction"
    t.jsonb "request_settings", default: {}, null: false
    t.index ["visibility_study_id", "task_key", "attempt"], name: "unique_visibility_call_attempt", unique: true
    t.index ["visibility_study_id"], name: "index_visibility_calls_on_visibility_study_id"
  end

  create_table "visibility_events", force: :cascade do |t|
    t.bigint "visibility_study_id", null: false
    t.string "kind", default: "status", null: false
    t.text "message", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["visibility_study_id"], name: "index_visibility_events_on_visibility_study_id"
  end

  create_table "visibility_observations", force: :cascade do |t|
    t.bigint "visibility_study_id", null: false
    t.string "question_key", null: false
    t.integer "repetition", null: false
    t.string "status", default: "queued", null: false
    t.text "answer"
    t.string "model_version"
    t.jsonb "citations", default: [], null: false
    t.jsonb "analysis", default: {}, null: false
    t.text "error_message"
    t.datetime "observed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["visibility_study_id", "question_key", "repetition"], name: "unique_visibility_observation", unique: true
    t.index ["visibility_study_id"], name: "index_visibility_observations_on_visibility_study_id"
  end

  create_table "visibility_studies", force: :cascade do |t|
    t.bigint "brand_id", null: false
    t.bigint "brand_brief_id", null: false
    t.string "status", default: "queued", null: false
    t.string "stage", default: "interpreting", null: false
    t.string "control_action"
    t.string "pause_reason"
    t.integer "progress", default: 0, null: false
    t.jsonb "settings", default: {}, null: false
    t.jsonb "profile", default: {}, null: false
    t.jsonb "competitors", default: [], null: false
    t.jsonb "entities", default: [], null: false
    t.jsonb "panel", default: [], null: false
    t.string "panel_fingerprint"
    t.text "research"
    t.jsonb "research_sources", default: [], null: false
    t.jsonb "report", default: {}, null: false
    t.decimal "budget_usd", precision: 10, scale: 4, default: "3.0", null: false
    t.decimal "spent_usd", precision: 12, scale: 6, default: "0.0", null: false
    t.integer "request_count", default: 0, null: false
    t.integer "token_count", default: 0, null: false
    t.integer "search_count", default: 0, null: false
    t.text "error_message"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["brand_brief_id"], name: "index_visibility_studies_on_brand_brief_id"
    t.index ["brand_id"], name: "index_visibility_studies_on_brand_id"
    t.index ["brand_id"], name: "one_active_visibility_study", unique: true, where: "((status)::text = ANY ((ARRAY['queued'::character varying, 'interpreting'::character varying, 'researching'::character varying, 'planning'::character varying, 'measuring'::character varying, 'diagnosing'::character varying, 'paused'::character varying])::text[]))"
    t.check_constraint "progress >= 0 AND progress <= 100 AND budget_usd > 0::numeric AND spent_usd >= 0::numeric", name: "visibility_study_bounds"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "brand_brief_documents", "brand_briefs"
  add_foreign_key "brand_brief_documents", "brand_documents"
  add_foreign_key "brand_briefs", "brands"
  add_foreign_key "brand_document_links", "brand_documents"
  add_foreign_key "brand_document_links", "brands"
  add_foreign_key "brand_documents", "brand_imports"
  add_foreign_key "brand_imports", "users"
  add_foreign_key "brands", "users"
  add_foreign_key "findings", "scans"
  add_foreign_key "repositories", "users"
  add_foreign_key "scan_events", "scans"
  add_foreign_key "scans", "repositories"
  add_foreign_key "visibility_actions", "repositories", on_delete: :nullify
  add_foreign_key "visibility_actions", "scans", on_delete: :nullify
  add_foreign_key "visibility_actions", "visibility_studies"
  add_foreign_key "visibility_calls", "visibility_studies"
  add_foreign_key "visibility_events", "visibility_studies"
  add_foreign_key "visibility_observations", "visibility_studies"
  add_foreign_key "visibility_studies", "brand_briefs"
  add_foreign_key "visibility_studies", "brands"
end

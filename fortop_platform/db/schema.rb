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

ActiveRecord::Schema[8.1].define(version: 2026_10_21_000100) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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
    t.index ["repository_id", "created_at"], name: "index_scans_on_repository_id_and_created_at"
    t.index ["repository_id"], name: "index_scans_on_repository_id"
    t.index ["repository_id"], name: "one_active_scan_per_repository", unique: true, where: "((status)::text = ANY ((ARRAY['queued'::character varying, 'discovering'::character varying, 'analyzing'::character varying, 'remediating'::character varying, 'validating'::character varying, 'publishing'::character varying])::text[]))"
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

  add_foreign_key "findings", "scans"
  add_foreign_key "repositories", "users"
  add_foreign_key "scan_events", "scans"
  add_foreign_key "scans", "repositories"
end

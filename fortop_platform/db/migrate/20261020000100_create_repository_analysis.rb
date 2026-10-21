class CreateRepositoryAnalysis < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.bigint :github_id, null: false
      t.string :login, null: false
      t.string :name
      t.string :email
      t.string :avatar_url
      t.text :github_token, null: false
      t.timestamps
    end
    add_index :users, :github_id, unique: true

    create_table :repositories do |t|
      t.references :user, null: false, foreign_key: true
      t.bigint :github_id, null: false
      t.string :full_name, null: false
      t.text :description
      t.string :default_branch, null: false, default: "main"
      t.string :html_url, null: false
      t.string :language
      t.boolean :private, null: false, default: false
      t.datetime :connected_at, null: false
      t.timestamps
    end
    add_index :repositories, [ :user_id, :github_id ], unique: true

    create_table :scans do |t|
      t.references :repository, null: false, foreign_key: true
      t.string :status, null: false, default: "queued"
      t.integer :progress, null: false, default: 0
      t.text :summary
      t.text :error_message
      t.string :base_sha
      t.string :branch_name
      t.string :pull_request_url
      t.integer :pull_request_number
      t.datetime :started_at
      t.datetime :finished_at
      t.jsonb :metadata, null: false, default: {}
      t.jsonb :validation_results, null: false, default: []
      t.jsonb :changed_files, null: false, default: []
      t.integer :agent_steps, null: false, default: 0
      t.timestamps
    end
    add_index :scans, [ :repository_id, :created_at ]
    add_index :scans, :repository_id, unique: true,
      where: "status IN ('queued', 'discovering', 'analyzing', 'remediating', 'validating', 'publishing')",
      name: "one_active_scan_per_repository"
    add_check_constraint :scans, "progress BETWEEN 0 AND 100", name: "scan_progress_range"

    create_table :findings do |t|
      t.references :scan, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description, null: false
      t.string :severity, null: false, default: "medium"
      t.string :category, null: false
      t.string :file_path
      t.integer :line_number
      t.text :evidence
      t.text :recommendation
      t.boolean :automatable, null: false, default: true
      t.string :status, null: false, default: "open"
      t.string :issue_url
      t.integer :issue_number
      t.string :fingerprint, null: false
      t.timestamps
    end
    add_index :findings, [ :scan_id, :fingerprint ], unique: true

    create_table :scan_events do |t|
      t.references :scan, null: false, foreign_key: true
      t.string :kind, null: false, default: "status"
      t.text :message, null: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :scan_events, [ :scan_id, :created_at ]
  end
end

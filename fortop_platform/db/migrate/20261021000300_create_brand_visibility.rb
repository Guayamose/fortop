class CreateBrandVisibility < ActiveRecord::Migration[8.1]
  def change
    create_table :brands do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :website, null: false
      t.text :brief, null: false
      t.jsonb :markets, null: false, default: []
      t.jsonb :aliases, null: false, default: []
      t.text :known_competitors
      t.jsonb :context_overrides, null: false, default: {}
      t.timestamps
    end
    create_table :brand_briefs do |t|
      t.references :brand, null: false, foreign_key: true
      t.integer :version, null: false
      t.text :content, null: false
      t.jsonb :context, null: false, default: {}
      t.timestamps
    end
    add_index :brand_briefs, [ :brand_id, :version ], unique: true
    create_table :visibility_studies do |t|
      t.references :brand, null: false, foreign_key: true
      t.references :brand_brief, null: false, foreign_key: true
      t.string :status, null: false, default: "queued"
      t.string :stage, null: false, default: "interpreting"
      t.string :control_action
      t.string :pause_reason
      t.integer :progress, null: false, default: 0
      t.jsonb :settings, null: false, default: {}
      t.jsonb :profile, null: false, default: {}
      t.jsonb :competitors, null: false, default: []
      t.jsonb :entities, null: false, default: []
      t.jsonb :panel, null: false, default: []
      t.string :panel_fingerprint
      t.text :research
      t.jsonb :research_sources, null: false, default: []
      t.jsonb :report, null: false, default: {}
      t.decimal :budget_usd, precision: 10, scale: 4, null: false, default: 3
      t.decimal :spent_usd, precision: 12, scale: 6, null: false, default: 0
      t.integer :request_count, null: false, default: 0
      t.integer :token_count, null: false, default: 0
      t.integer :search_count, null: false, default: 0
      t.text :error_message
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :visibility_studies, :brand_id, unique: true, name: "one_active_visibility_study",
      where: "status IN ('queued','interpreting','researching','planning','measuring','diagnosing','paused')"
    add_check_constraint :visibility_studies, "progress BETWEEN 0 AND 100 AND budget_usd > 0 AND spent_usd >= 0", name: "visibility_study_bounds"
    create_table :visibility_calls do |t|
      t.references :visibility_study, null: false, foreign_key: true
      t.string :task_key, null: false
      t.integer :attempt, null: false, default: 1
      t.string :status, null: false, default: "running"
      t.string :model, null: false
      t.string :model_version
      t.boolean :grounded, null: false, default: false
      t.text :response_text
      t.jsonb :citations, null: false, default: []
      t.jsonb :search_queries, null: false, default: []
      t.text :search_entry_point
      t.jsonb :usage, null: false, default: {}
      t.decimal :cost_usd, precision: 12, scale: 6, null: false, default: 0
      t.text :error_message
      t.boolean :retryable, null: false, default: false
      t.datetime :observed_at
      t.timestamps
    end
    add_index :visibility_calls, [ :visibility_study_id, :task_key, :attempt ], unique: true, name: "unique_visibility_call_attempt"
    create_table :visibility_observations do |t|
      t.references :visibility_study, null: false, foreign_key: true
      t.string :question_key, null: false
      t.integer :repetition, null: false
      t.string :status, null: false, default: "queued"
      t.text :answer
      t.string :model_version
      t.jsonb :citations, null: false, default: []
      t.jsonb :analysis, null: false, default: {}
      t.text :error_message
      t.datetime :observed_at
      t.timestamps
    end
    add_index :visibility_observations, [ :visibility_study_id, :question_key, :repetition ], unique: true, name: "unique_visibility_observation"
    create_table :visibility_events do |t|
      t.references :visibility_study, null: false, foreign_key: true
      t.string :kind, null: false, default: "status"
      t.text :message, null: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    create_table :visibility_actions do |t|
      t.references :visibility_study, null: false, foreign_key: true
      t.references :repository, foreign_key: { on_delete: :nullify }
      t.references :scan, foreign_key: { on_delete: :nullify }
      t.string :fingerprint, null: false
      t.string :title, null: false
      t.text :description, null: false
      t.string :kind, null: false, default: "editorial"
      t.string :priority, null: false, default: "medium"
      t.string :effort, null: false, default: "medium"
      t.string :status, null: false, default: "planned"
      t.jsonb :observation_ids, null: false, default: []
      t.timestamps
    end
    add_index :visibility_actions, [ :visibility_study_id, :fingerprint ], unique: true, name: "unique_visibility_action"
  end
end

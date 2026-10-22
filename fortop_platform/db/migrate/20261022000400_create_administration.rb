class CreateAdministration < ActiveRecord::Migration[8.1]
  def change
    create_table :github_access_grants do |t|
      t.bigint :github_id, null: false
      t.string :login, null: false
      t.timestamps
    end
    add_index :github_access_grants, :github_id, unique: true
    add_check_constraint :github_access_grants, "github_id > 0", name: "github_access_positive_id"

    create_table :platform_settings do |t|
      t.string :key, null: false
      t.string :value, null: false
      t.timestamps
    end
    add_index :platform_settings, :key, unique: true

    create_table :admin_audit_events do |t|
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.string :action, null: false
      t.string :subject, null: false
      t.jsonb :details, null: false, default: {}
      t.timestamps
    end
    add_index :admin_audit_events, :created_at
  end
end

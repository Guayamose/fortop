class AddScanExecutionControls < ActiveRecord::Migration[8.1]
  def change
    add_column :scans, :control_action, :string
    add_column :scans, :execution_state, :text
    remove_index :scans, :repository_id, name: "one_active_scan_per_repository", unique: true,
      where: "status IN ('queued', 'discovering', 'analyzing', 'remediating', 'validating', 'publishing')"
    add_index :scans, :repository_id, unique: true, name: "one_active_scan_per_repository",
      where: "status IN ('queued', 'discovering', 'analyzing', 'remediating', 'validating', 'publishing', 'paused')"
  end
end

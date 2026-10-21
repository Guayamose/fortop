class AddPublicationChangesToScans < ActiveRecord::Migration[8.1]
  def change
    add_column :scans, :publication_changes, :text
  end
end

class AddFindingExplanations < ActiveRecord::Migration[8.1]
  def change
    add_column :findings, :impact, :text
    add_column :findings, :verification, :text
  end
end

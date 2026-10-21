class AddRemediationRationaleToFindings < ActiveRecord::Migration[8.1]
  def change
    add_column :findings, :remediation_rationale, :text
  end
end

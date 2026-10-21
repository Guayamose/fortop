class RecordVisibilityRequestContext < ActiveRecord::Migration[8.1]
  def change
    add_column :visibility_calls, :input_prompt, :text
    add_column :visibility_calls, :system_instruction, :text
    add_column :visibility_calls, :request_settings, :jsonb, default: {}, null: false
  end
end

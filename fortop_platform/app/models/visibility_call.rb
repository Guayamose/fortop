class VisibilityCall < ApplicationRecord
  encrypts :response_text, :input_prompt, :system_instruction
  belongs_to :visibility_study
  validates :task_key, :model, presence: true
  validates :status, inclusion: { in: %w[running succeeded failed uncertain] }
end

class VisibilityObservation < ApplicationRecord
  encrypts :answer
  belongs_to :visibility_study
  validates :question_key, presence: true
  validates :repetition, numericality: { only_integer: true, in: 1..5 }
  validates :status, inclusion: { in: %w[queued answered completed failed] }

  def question
    visibility_study.panel.find { |question| question["key"] == question_key } || {}
  end
end

class VisibilityEvent < ApplicationRecord
  belongs_to :visibility_study
  validates :kind, :message, presence: true
end

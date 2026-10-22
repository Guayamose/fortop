class AdminAuditEvent < ApplicationRecord
  belongs_to :actor, class_name: "User"
  validates :action, :subject, presence: true
  scope :recent, -> { order(created_at: :desc, id: :desc) }
end

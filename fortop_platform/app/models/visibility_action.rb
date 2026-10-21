class VisibilityAction < ApplicationRecord
  belongs_to :visibility_study
  belongs_to :repository, optional: true
  belongs_to :scan, optional: true
  validate :owned_repository

  def owned_repository
    if repository && repository.user_id != visibility_study.brand.user_id
      errors.add(:repository, "no pertenece al dueño de esta marca")
    end
    errors.add(:scan, "no corresponde al repositorio") if scan && scan.repository_id != repository_id
  end

  validates :title, :description, :fingerprint, presence: true
  validates :kind, inclusion: { in: %w[technical editorial positioning] }
  validates :priority, :effort, inclusion: { in: %w[high medium low] }
  validates :status, inclusion: { in: %w[planned in_progress done dismissed] }
end

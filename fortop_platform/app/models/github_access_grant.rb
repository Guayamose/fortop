class GithubAccessGrant < ApplicationRecord
  validates :github_id, numericality: { only_integer: true, greater_than: 0 }, uniqueness: true
  validates :login, format: { with: /\A[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,37}[a-zA-Z0-9])?\z/ }
  validate :owner_needs_no_grant

  private

  def owner_needs_no_grant
    errors.add(:base, "Tu cuenta de administrador tiene acceso permanente.") if github_id == User::OWNER_GITHUB_ID
  end
end

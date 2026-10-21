class Repository < ApplicationRecord
  belongs_to :user
  has_many :scans, dependent: :destroy

  before_validation { self.connected_at ||= Time.current }
  before_destroy :prevent_disconnect_during_scan, prepend: true

  validates :github_id, presence: true, uniqueness: { scope: :user_id }
  validates :full_name, format: { with: %r{\A[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\z} }
  validates :default_branch, :html_url, :connected_at, presence: true
  validates :html_url, format: { with: %r{\Ahttps://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\z} }

  def display_name
    full_name.split("/").last
  end

  def latest_scan
    scans.recent.first
  end

  private

  def prevent_disconnect_during_scan
    return unless scans.active.exists?

    errors.add(:base, "Espera a que termine el análisis antes de desconectar el repositorio.")
    throw :abort
  end
end

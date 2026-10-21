require "digest"

class Finding < ApplicationRecord
  belongs_to :scan

  enum :severity, { high: "high", medium: "medium", low: "low" }, prefix: true, validate: true
  enum :status, { open: "open", fixed: "fixed", manual: "manual" }, prefix: true, validate: true

  before_validation :assign_fingerprint

  validates :title, :description, :category, :evidence, presence: true
  validates :fingerprint, uniqueness: { scope: :scan_id }
  validates :line_number, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  private

  def assign_fingerprint
    self.fingerprint ||= Digest::SHA256.hexdigest([ category, file_path, title.to_s.downcase.strip ].join(":"))
  end
end

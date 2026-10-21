class ScanEvent < ApplicationRecord
  belongs_to :scan
  validates :kind, :message, presence: true
end

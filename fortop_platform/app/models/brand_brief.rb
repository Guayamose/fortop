class BrandBrief < ApplicationRecord
  encrypts :content
  belongs_to :brand
  has_many :visibility_studies, dependent: :restrict_with_error
  validates :version, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :brand_id }
  validates :content, presence: true
  before_update { throw :abort }
end

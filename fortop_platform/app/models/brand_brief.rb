class BrandBrief < ApplicationRecord
  encrypts :content
  belongs_to :brand
  has_and_belongs_to_many :documents, class_name: "BrandDocument", join_table: :brand_brief_documents, association_foreign_key: :brand_document_id
  has_many :visibility_studies, dependent: :restrict_with_error
  validates :version, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :brand_id }
  validates :content, presence: true
  before_update { throw :abort }
end

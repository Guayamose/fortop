class BrandDocument < ApplicationRecord
  belongs_to :brand_import
  has_one_attached :file
  encrypts :extracted_text
  has_and_belongs_to_many :brands, join_table: :brand_document_links
  has_and_belongs_to_many :brand_briefs, join_table: :brand_brief_documents

  before_update :preserve_completed_source
  before_destroy :preserve_referenced_source, prepend: true

  def context
    { "id" => id, "filename" => file.filename.to_s, "text" => extracted_text }
  end

  private

  def preserve_completed_source
    throw :abort if brand_import.completed? && extracted_text_changed?
  end

  def preserve_referenced_source
    throw :abort if brands.exists? || brand_briefs.exists?
  end
end

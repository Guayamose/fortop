class Brand < ApplicationRecord
  encrypts :brief
  belongs_to :user
  has_many :visibility_studies, dependent: :destroy
  has_many :brand_briefs, dependent: :destroy
  has_and_belongs_to_many :documents, class_name: "BrandDocument", join_table: :brand_document_links, association_foreign_key: :brand_document_id
  validate :valid_documents
  validates :name, length: { in: 2..120 }
  validates :brief, length: { in: 30..20_000 }
  validates :known_competitors, length: { maximum: 4000 }
  validate :valid_aliases
  validates :website, length: { maximum: 500 }
  validate :public_website
  validate :valid_markets
  before_validation :normalize_fields
  after_save :snapshot_brief!, if: :saved_context_changed?
  before_destroy :prevent_active_study, prepend: true

  def document_ids=(ids)
    @documents_changed = Array(ids).reject(&:blank?).map(&:to_i).sort != document_ids.sort
    super
  end

  def markets_text
    markets.map { |market| "#{market['name']} | #{market['language']}" }.join("\n")
  end

  def markets_text=(value)
    self.markets = value.to_s.split(/[\n;]/).reject(&:blank?).map do |line|
      name, language = line.split("|", 2).map(&:strip)
      { "name" => name, "language" => language.presence || "es" }
    end.uniq
  end

  def aliases_text
    aliases.join(", ")
  end

  def aliases_text=(value)
    self.aliases = value.to_s.split(/[,\n]/).map(&:strip).reject(&:blank?).uniq.first(15)
  end

  def latest_study
    visibility_studies.order(created_at: :desc, id: :desc).first
  end

  def current_brief
    brand_briefs.order(version: :desc).first!
  end

  private

  def normalize_fields
    self.name = name.to_s.strip
    self.website = website.to_s.strip
    self.website = "https://#{website}" unless website.blank? || website.match?(%r{\Ahttps?://}i)
  end

  def valid_aliases
    errors.add(:aliases, "usa hasta 15 nombres de menos de 120 caracteres") unless aliases.is_a?(Array) && aliases.size <= 15 && aliases.all? { |name| name.is_a?(String) && name.length.between?(2, 120) }
  end

  def public_website
    errors.add(:website, "debe ser una web pública con un dominio válido") unless Visibility::Urls.public_url(website)
  end

  def valid_markets
    valid = markets.is_a?(Array) && markets.size.between?(1, 8) && markets.all? do |market|
      market.is_a?(Hash) && market["name"].is_a?(String) && market["name"].length.between?(2, 80) && market["language"].to_s.match?(/\A[a-z]{2}(?:-[A-Z]{2})?\z/)
    end
    errors.add(:markets, "indica de 1 a 8 mercados con su idioma, por ejemplo España | es") unless valid
  end

  def saved_context_changed?
    @documents_changed || (saved_changes.keys & %w[name website brief markets aliases known_competitors context_overrides]).any?
  end

  def snapshot_brief!
    with_lock do
      brand_briefs.create!(documents: documents.to_a, version: (brand_briefs.maximum(:version) || 0) + 1, content: brief,
        context: attributes.slice("name", "website", "markets", "aliases", "known_competitors", "context_overrides"))
    end
    @documents_changed = false
  end

  def valid_documents
    sources = documents.to_a
    if sources.size > BrandImports::Documents::MAX_FILES || sources.any? { |document| document.brand_import.user_id != user_id || !document.brand_import.completed? || !document.file.attached? }
      errors.add(:documents, "usa hasta 10 documentos de tu cuenta cuya lectura haya terminado")
      return
    end
    errors.add(:documents, "el contexto completo no puede superar 50 MB") if sources.sum { |document| document.file.byte_size } > BrandImports::Documents::MAX_TOTAL_BYTES
    errors.add(:documents, "el contexto completo no puede superar 300.000 caracteres") if sources.sum { |document| document.extracted_text.to_s.length } > BrandImports::Documents::MAX_TEXT
  end

  def prevent_active_study
    return unless visibility_studies.active.exists?
    errors.add(:base, "Cancela el estudio en curso antes de eliminar la marca.")
    throw :abort
  end
end

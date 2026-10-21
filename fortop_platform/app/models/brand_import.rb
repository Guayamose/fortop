class BrandImport < ApplicationRecord
  belongs_to :user
  has_many :documents, class_name: "BrandDocument", dependent: :destroy
  serialize :input_fields, coder: JSON
  serialize :result, coder: JSON
  encrypts :input_fields, :result
  enum :status, %w[queued extracting interpreting completed failed].index_with(&:itself), validate: true

  def active?
    queued? || extracting? || interpreting?
  end

  def expire_if_stale!
    with_lock do
      if active? && updated_at < 10.minutes.ago
        update!(status: "failed", retryable: request_count < 3, error_message: "La lectura se ha interrumpido. Puedes reintentar sin volver a subir los archivos.")
      end
    end
  end
end

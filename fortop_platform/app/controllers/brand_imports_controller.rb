class BrandImportsController < ApplicationController
  before_action :set_import, only: %i[show retry]
  before_action :check_new_work, only: %i[create retry]

  def create
    files = Array(params[:files]).reject(&:blank?)
    BrandImports::Documents.validate_uploads!(files)
    import = current_user.brand_imports.create!(input_fields: params.permit(fields: BrandImports::Processor::FIELDS.keys).fetch(:fields, {}).to_h.transform_values { |value| value.to_s.first(20_000) })
    begin
      files.each do |upload|
        document = import.documents.build
        extension = File.extname(upload.original_filename).downcase
        document.file.attach(io: upload.tempfile, filename: upload.original_filename, content_type: BrandImports::Documents::MIME_TYPES.fetch(extension), identify: false)
        document.save!
      end
      enqueue!(import)
    rescue StandardError => error
      import.update!(status: "failed", error_message: "No se han podido guardar los archivos. Vuelve a subirlos.")
      Rails.logger.error("Brand import=#{import.id} upload failed class=#{error.class.name}")
      return render json: { error: import.error_message }, status: :unprocessable_entity
    end
    render json: payload(import), status: :accepted
  rescue Visibility::Error => error
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def show
    @import.expire_if_stale!
    render json: payload(@import)
  end

  def retry
    @import.with_lock do
      unless @import.failed? && @import.retryable? && @import.request_count < 3
        return render json: { error: "Esta lectura no está disponible para reintentar." }, status: :unprocessable_entity
      end
      @import.update!(status: "queued", error_message: nil, retryable: false)
    end
    enqueue!(@import)
    render json: payload(@import), status: :accepted
  end

  private

  def check_new_work
    render json: { error: "Las nuevas ejecuciones están pausadas por el administrador." }, status: :service_unavailable unless PlatformSetting.new_work_enabled?
  end

  def set_import
    @import = current_user.brand_imports.find(params[:id])
  end

  def enqueue!(import)
    raise ActiveJob::EnqueueError unless BrandImportJob.perform_later(import.id)
  rescue StandardError
    import.update!(status: "failed", error_message: "No se ha podido iniciar la lectura. Puedes reintentarlo.", retryable: true)
  end

  def payload(import)
    { id: import.id, status: import.status, url: brand_import_path(import), retry_url: retry_brand_import_path(import), retryable: import.retryable?,
      error: import.error_message, fields: import.completed? ? import.result.fetch("fields") : {}, warnings: import.completed? ? import.result.fetch("warnings") : [],
      documents: import.documents.includes(file_attachment: :blob).map { |document| { id: document.id, name: document.file.filename.to_s, size: document.file.byte_size, url: brand_document_path(document) } } }
  end
end

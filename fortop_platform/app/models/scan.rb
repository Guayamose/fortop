class Scan < ApplicationRecord
  encrypts :publication_changes, :execution_state

  ACTIVE_STATUSES = %w[queued discovering analyzing remediating validating publishing paused].freeze
  STATUS_LABELS = {
    "queued" => "En cola", "discovering" => "Preparando repositorio",
    "analyzing" => "Agente de análisis", "remediating" => "Agente de remediación",
    "validating" => "Verificando cambios", "publishing" => "Publicando en GitHub",
    "paused" => "En pausa", "completed" => "Completado", "failed" => "Error", "cancelled" => "Cancelado"
  }.freeze

  belongs_to :repository
  has_many :findings, dependent: :destroy
  has_many :scan_events, dependent: :destroy

  enum :status, STATUS_LABELS.keys.index_with(&:itself), validate: true
  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :active, -> { where(status: ACTIVE_STATUSES) }

  validates :progress, numericality: { only_integer: true, in: 0..100 }
  validates :control_action, inclusion: { in: %w[pause cancel restart] }, allow_nil: true
  validate :one_active_scan, on: :create

  def active?
    ACTIVE_STATUSES.include?(status)
  end

  def work_pending?
    active? && (!paused? || control_action.present?)
  end

  def publication_prepared?
    validation_results.present? && validation_results.all? { |result| result["passed"] } &&
      (publication_changes.present? || (metadata.dig("publication", "commit_sha").present? && changed_files.present?))
  end

  def publication_retryable?
    failed? && publication_prepared?
  end

  def status_label
    STATUS_LABELS.fetch(status, status.to_s.humanize)
  end

  def record_event!(message, kind: "status", metadata: {})
    scan_events.create!(message: message, kind: kind, metadata: metadata)
  end

  def advance!(new_status, progress:, message:)
    transaction do
      update!(status: new_status, progress: progress,
        started_at: started_at || Time.current,
        finished_at: %w[completed failed cancelled].include?(new_status.to_s) ? Time.current : nil)
      record_event!(message)
    end
  end

  def expire_if_stale!(now: Time.current)
    return self unless active? && !paused? && updated_at < now - 30.minutes

    with_lock do
      last_activity = [ updated_at, scan_events.maximum(:created_at) ].compact.max
      if active? && !paused? && last_activity < now - 30.minutes
        message = "La ejecución se ha detenido tras 30 minutos sin actividad. Puedes iniciar un nuevo análisis."
        update!(status: "failed", error_message: message, finished_at: now)
        record_event!(message, kind: "warning")
      end
    end
    self
  end

  private

  def one_active_scan
    return unless active? && repository && repository.scans.active.exists?

    errors.add(:base, "Ya hay un análisis en curso para este repositorio.")
  end
end

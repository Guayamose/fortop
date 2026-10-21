class VisibilityStudy < ApplicationRecord
  encrypts :research
  ACTIVE_STATUSES = %w[queued interpreting researching planning measuring diagnosing paused].freeze
  LABELS = { "queued" => "En cola", "interpreting" => "Interpretando el brief", "researching" => "Investigando el mercado", "planning" => "Preparando las preguntas", "measuring" => "Midiendo la visibilidad", "diagnosing" => "Preparando el diagnóstico", "paused" => "En pausa", "completed" => "Completado", "failed" => "Interrumpido", "cancelled" => "Cancelado" }.freeze
  belongs_to :brand
  belongs_to :brand_brief
  has_many :visibility_calls, dependent: :destroy
  has_many :visibility_observations, dependent: :destroy
  has_many :visibility_events, dependent: :destroy
  has_many :visibility_actions, dependent: :destroy
  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :active, -> { where(status: ACTIVE_STATUSES) }
  enum :status, LABELS.keys.index_with(&:itself), validate: true
  validates :stage, inclusion: { in: %w[interpreting researching planning measuring diagnosing] }
  validates :control_action, inclusion: { in: %w[pause cancel restart] }, allow_nil: true
  validates :budget_usd, numericality: { greater_than: 0, less_than_or_equal_to: 50 }
  validates :progress, numericality: { only_integer: true, in: 0..100 }
  validate :matching_brief

  def active?
    ACTIVE_STATUSES.include?(status)
  end

  def work_pending?
    active? && (!paused? || control_action.present?)
  end

  def status_label
    LABELS.fetch(status)
  end

  def record_event!(message, kind: "status", metadata: {})
    visibility_events.create!(message: message, kind: kind, metadata: metadata)
  end

  def advance!(next_stage, progress:, message:)
    update!(stage: next_stage, status: next_stage, progress: progress)
    record_event!(message)
  end

  def expected_observations
    panel.size * settings.fetch("repetitions", 2).to_i
  end

  def expire_if_stale!
    return unless work_pending? && updated_at < 30.minutes.ago
    with_lock do
      return unless work_pending? && updated_at < 30.minutes.ago
      update!(status: "failed", finished_at: Time.current, error_message: "El ejecutor dejó de registrar actividad. Puedes recuperar el estudio sin repetir las respuestas guardadas.")
      record_event!(error_message, kind: "warning")
    end
  end

  private

  def matching_brief
    errors.add(:brand_brief, "no pertenece a esta marca") if brand_brief && brand_brief.brand_id != brand_id
  end
end

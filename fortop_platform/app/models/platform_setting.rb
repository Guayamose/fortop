class PlatformSetting < ApplicationRecord
  # Only operational values are editable. Credentials always stay in the
  # deployment environment; neither arbitrary ENV keys nor secrets are accepted.
  DEFINITIONS = {
    "NEW_WORK_ENABLED" => { label: "Permitir nuevas ejecuciones", default: "true", choices: %w[true false], group: :access },
    "GEMINI_MODEL" => { label: "Modelo de repositorios", default: "gemini-3.5-flash-lite", model: true, group: :repositories },
    "AGENT_MAX_TOTAL_TOKENS" => { label: "Tokens por análisis · 0 sin límite", default: "0", range: 0..100_000_000, group: :repositories },
    "AGENT_MAX_OUTPUT_TOKENS" => { label: "Tokens de salida por petición", default: "16384", range: 256..65_536, group: :repositories },
    "AGENT_MAX_TURNS" => { label: "Turnos · 0 sin límite", default: "0", range: 0..100_000, group: :repositories },
    "AGENT_MAX_TOOL_CALLS" => { label: "Herramientas · 0 sin límite", default: "0", range: 0..1_000_000, group: :repositories },
    "AGENT_TIMEOUT_SECONDS" => { label: "Duración en segundos · 0 sin límite", default: "0", range: 0..604_800, group: :repositories },
    "AGENT_CONTEXT_MAX_BYTES" => { label: "Contexto antes de resumir · bytes", default: "120000", range: 4_000..10_000_000, group: :repositories },
    "VISIBILITY_GEMINI_MODEL" => { label: "Modelo de visibilidad", default: "gemini-3.5-flash-lite", choices: Visibility::Settings::PRICING.keys, group: :visibility },
    "VISIBILITY_DAILY_BUDGET_USD" => { label: "Presupuesto diario por usuario · USD", default: "10", decimal: true, range: BigDecimal("0.01")..BigDecimal("1000"), group: :visibility },
    "VISIBILITY_MAX_REQUESTS" => { label: "Peticiones por estudio", default: "1500", range: 1..100_000, group: :visibility },
    "VISIBILITY_MAX_TOKENS" => { label: "Tokens por estudio", default: "2000000", range: 1..100_000_000, group: :visibility }
  }.freeze

  validates :key, inclusion: { in: DEFINITIONS.keys }, uniqueness: true
  validate :valid_value

  def self.fetch(key, default = nil)
    raise ArgumentError, "Unknown operational setting" unless DEFINITIONS.key?(key)
    value = find_by(key: key)&.value || ENV[key].presence
    return value unless value.nil?
    return default unless default.nil?
    key == "VISIBILITY_GEMINI_MODEL" ? fetch("GEMINI_MODEL") : DEFINITIONS.fetch(key).fetch(:default)
  end

  def self.new_work_enabled?
    fetch("NEW_WORK_ENABLED") == "true"
  end

  private

  def valid_value
    definition = DEFINITIONS[key]
    return unless definition
    valid = if definition[:choices]
      definition[:choices].include?(value)
    elsif definition[:model]
      value.to_s.match?(/\Agemini-[a-z0-9.-]{1,90}\z/)
    else
      number = definition[:decimal] ? BigDecimal(value.to_s) : Integer(value.to_s, 10)
      definition.fetch(:range).cover?(number) && number.finite?
    end
    errors.add(:value, "no es válido para #{definition[:label]}") unless valid
  rescue ArgumentError, TypeError
    errors.add(:value, "no es válido para #{definition[:label]}")
  end
end

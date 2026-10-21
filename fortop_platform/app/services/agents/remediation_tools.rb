module Agents
  class RemediationTools < RepositoryTools
    def initialize(workspace:, scan:, validator:)
      super(workspace: workspace, scan: scan)
      @validator = validator
    end

    def declarations
      super + [
        function("replace_text", "Replace exactly one occurrence in a file. Prefer small, targeted edits. finding_ids must reference accepted automatable findings.", { path: string, old_text: string, new_text: string, finding_ids: { type: "ARRAY", items: integer } }, required: %w[path old_text new_text finding_ids]),
        function("write_file", "Write the complete content of an eligible file. Read existing files first. No credentials, dependencies, workflows, tests, shell scripts or invented business facts.", { path: string, content: string, finding_ids: { type: "ARRAY", items: integer } }, required: %w[path content finding_ids]),
        function("discard_changes", "Discard a proposed edit when it cannot be validated safely.", { path: string }, required: %w[path]),
        function("validate_changes", "Run deterministic syntax and safety checks on all proposed changes. Inspect failures, repair and rerun. No project code executes on the host.", {}),
        function("mark_manual", "Explain why an accepted finding cannot be safely corrected automatically. Never claim a change is fixed without validated code.", { finding_id: integer, reason: string }, required: %w[finding_id reason])
      ]
    end

    def call(name, arguments)
      case name
      when "write_file", "replace_text"
        ids = valid_finding_ids(arguments.fetch("finding_ids"))
        if name == "write_file"
          @workspace.write(arguments.fetch("path"), arguments.fetch("content"), finding_ids: ids)
        else
          @workspace.replace(arguments.fetch("path"), arguments.fetch("old_text"), arguments.fetch("new_text"), finding_ids: ids)
        end
      when "discard_changes" then @workspace.discard(arguments.fetch("path"))
      when "validate_changes"
        results = @validator.call
        @scan.record_event!("Verificación de #{workspace.changes.size} archivos: #{results.all? { |result| result["passed"] } ? "correcta" : "requiere correcciones"}.", kind: "validation", metadata: { checks: results })
        { "passed" => results.all? { |result| result["passed"] }, "checks" => results }
      when "mark_manual"
        finding = @scan.findings.find_by(id: arguments.fetch("finding_id"))
        raise ToolError, "El hallazgo no pertenece a este análisis." unless finding
        reason = arguments.fetch("reason").to_s.strip.truncate(2000)
        raise ToolError, "Indica el motivo de la intervención manual." if reason.blank?
        finding.update!(status: "manual", automatable: false, recommendation: "#{finding.recommendation}\n\nIntervención manual: #{reason}".truncate(6000))
        { "finding_id" => finding.id, "status" => "manual" }
      else super
      end
    rescue KeyError
      raise ToolError, "Faltan argumentos obligatorios para la herramienta."
    end

    private

    def valid_finding_ids(ids)
      raise ToolError, "Indica los identificadores de los hallazgos que corrige el archivo." unless ids.is_a?(Array) && ids.present?
      ids = ids.map { |id| Integer(id) }.uniq
      allowed = @scan.findings.where(id: ids, automatable: true).pluck(:id)
      raise ToolError, "Solo se corrigen hallazgos automatizables de este análisis." unless allowed.sort == ids.sort
      ids
    rescue ArgumentError, TypeError
      raise ToolError, "Los identificadores de hallazgos no son válidos."
    end
  end
end

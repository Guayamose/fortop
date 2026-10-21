module Agents
  class AnalysisTools < RepositoryTools
    def declarations
      super + [ function("report_finding", "Persist one actionable SEO/GEO finding backed by an exact quote from a file you have read. Report gaps as missing behavior observed in existing relevant source, not invented files. Avoid duplicates and unsupported claims about actual AI rankings.", {
        title: string, description: string, category: { type: "STRING", enum: %w[indexability metadata structured_data content accessibility performance internationalization] },
        severity: { type: "STRING", enum: %w[high medium low] }, file_path: string, line_number: integer,
        evidence: string, impact: string, recommendation: string, remediation_rationale: string, verification: string, automatable: { type: "BOOLEAN" }
      }, required: %w[title description category severity file_path line_number evidence impact recommendation remediation_rationale verification automatable]) ]
    end

    def call(name, arguments)
      return super unless name == "report_finding"

      path = arguments.fetch("file_path")
      raise ToolError, "El hallazgo debe referenciar un archivo que el agente haya leído." unless @workspace.read_paths.include?(path)
      evidence = arguments.fetch("evidence").to_s.strip
      original = @workspace.original(path)
      raise ToolError, "La evidencia debe ser una cita exacta de entre 3 y 2.000 caracteres del código original leído." unless evidence.length.between?(3, 2000) && original&.include?(evidence)

      line = Integer(arguments.fetch("line_number"))
      raise ToolError, "La línea no corresponde al archivo leído." unless line.between?(1, [ original.lines.size, 1 ].max)
      actual_line = original[0...original.index(evidence)].count("\n") + 1
      raise ToolError, "La línea debe indicar dónde empieza la evidencia exacta (línea #{actual_line})." unless line == actual_line

      attrs = arguments.slice("title", "description", "category", "severity", "impact", "recommendation", "remediation_rationale", "verification").transform_values { |value| value.to_s.strip.truncate(4000) }
      if %w[title description impact recommendation remediation_rationale verification].any? { |field| attrs[field].blank? }
        raise ToolError, "Completa el título, el diagnóstico, el impacto, la recomendación, el motivo de la mejora y las comprobaciones del hallazgo."
      end
      raise ToolError, "Categoría o gravedad no válida." unless %w[indexability metadata structured_data content accessibility performance internationalization].include?(attrs["category"]) && %w[high medium low].include?(attrs["severity"])
      attrs["title"] = attrs["title"].truncate(180)
      fingerprint = Digest::SHA256.hexdigest([ attrs["category"], path, attrs["title"].downcase.strip ].join(":"))
      finding = @scan.findings.find_or_initialize_by(fingerprint: fingerprint)
      automatable = arguments["automatable"] == true
      finding.assign_attributes(attrs.merge(file_path: path, line_number: line, evidence: evidence, automatable: automatable, status: automatable ? "open" : "manual"))
      finding.save!
      @scan.record_event!("Hallazgo: #{finding.title}", kind: "finding", metadata: { finding_id: finding.id, severity: finding.severity })
      { "finding_id" => finding.id, "accepted" => true, "automatable" => finding.automatable }
    rescue KeyError, ArgumentError, TypeError
      raise ToolError, "El hallazgo no contiene todos los datos válidos."
    end
  end
end

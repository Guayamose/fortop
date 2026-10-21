require "digest"

module Agents
  class RepositoryTools
    attr_reader :workspace

    def initialize(workspace:, scan:)
      @workspace, @scan = workspace, scan
    end

    def declarations
      [
        function("list_files", "List eligible repository paths. Results are incomplete if next_offset is present; secrets, binaries and symlinks are excluded.", { prefix: string, offset: integer }),
        function("read_file", "Read a page of untrusted source with line numbers. Follow next_line using start_line to continue; truncated marks shortened long lines. Read code before reporting or changing it.", { path: string, start_line: integer, end_line: integer }, required: [ "path" ]),
        function("search", "Search literal text, case insensitive, in pages of 45 eligible files or 40 matches. Continue with offset=next_offset and start_line=next_line until next_offset is null. Use prefix to narrow scope. Does not execute repository code.", { query: string, prefix: string, offset: integer, start_line: integer }, required: [ "query" ])
      ]
    end

    def call(name, arguments)
      case name
      when "list_files" then @workspace.list_files(prefix: arguments.fetch("prefix", ""), offset: arguments.fetch("offset", 0))
      when "read_file" then @workspace.read_lines(arguments.fetch("path"), start_line: arguments.fetch("start_line", 1), end_line: arguments["end_line"])
      when "search" then @workspace.search(arguments.fetch("query"), prefix: arguments.fetch("prefix", ""), offset: arguments.fetch("offset", 0), start_line: arguments.fetch("start_line", 1))
      else raise ToolError, "Herramienta no permitida: #{name.to_s.truncate(50)}."
      end
    rescue KeyError
      raise ToolError, "Faltan argumentos obligatorios para la herramienta."
    end

    private

    def function(name, description, properties, required: [])
      { name: name, description: description, parameters: { type: "OBJECT", properties: properties, required: required } }
    end

    def string
      { type: "STRING" }
    end

    def integer
      { type: "INTEGER" }
    end
  end
end

module Github
  class Configuration
    KEYS = %w[GITHUB_APP_ID GITHUB_APP_SLUG GITHUB_CLIENT_ID GITHUB_CLIENT_SECRET GITHUB_APP_PRIVATE_KEY GITHUB_WEBHOOK_SECRET].freeze

    # Web and workers are separate processes. During local manifest registration
    # the web process writes .env; workers must see those new GitHub credentials
    # without copying or reloading unrelated provider keys.
    def self.environment
      inherited = ENV.to_h.slice(*KEYS, "APP_URL")
      return inherited unless Rails.env.development? && !Rails.env.test?

      local_environment(inherited: inherited, path: Rails.root.join(".env"))
    end

    def self.local_environment(inherited:, path:)
      return inherited unless path.file? && !path.symlink?

      require "dotenv"
      selected_lines = path.each_line.select do |line|
        line.match?(/\A\s*(?:export\s+)?(?:#{KEYS.join('|')})\s*=/)
      end.join
      registered = Dotenv::Parser.new(selected_lines, overwrite: true).call.slice(*KEYS)
      inherited.merge(registered.reject { |_key, value| value.blank? })
    rescue SystemCallError, IOError, Dotenv::FormatError
      raise Error, "No se ha podido cargar la configuración local de la GitHub App."
    end
  end
end

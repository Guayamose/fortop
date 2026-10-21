module Github
  class Access
    MAX_PAGES = 100

    def self.user_client(user)
      if user.github_token_expires_at && user.github_token_expires_at <= 2.minutes.from_now
        # Refresh tokens rotate; locking prevents concurrent requests from using
        # the same refresh token and invalidating each other's credentials.
        user.with_lock do
          if user.github_token_expires_at && user.github_token_expires_at <= 2.minutes.from_now
            credentials = Github::OAuth.new.refresh(refresh_token: user.github_refresh_token)
            user.update!(github_token: credentials.fetch(:token),
              github_refresh_token: credentials.fetch(:refresh_token), github_token_expires_at: credentials[:expires_at])
          end
        end
      end
      Github::Client.new(token: user.github_token)
    end

    def self.repository_for(user, installation_id:, full_name:)
      client = user_client(user)
      installation = find_in_pages { |page| client.installations(page: page) }
        .find { |entry| entry["id"].to_s == installation_id.to_s && entry["suspended_at"].blank? }
      raise Error.new("No tienes acceso a esa instalación de GitHub.", status: 403) unless installation

      allowed = find_in_pages { |page| client.installation_repositories(installation_id, page: page) }
        .find { |entry| entry["full_name"].to_s.casecmp?(full_name.to_s) }
      raise Error.new("El repositorio no está autorizado para tu cuenta y esta GitHub App.", status: 403) unless allowed

      canonical = client.repository(allowed.fetch("full_name"))
      unless canonical["id"] == allowed["id"] && canonical.dig("permissions", "push") && !canonical["archived"] && !canonical["disabled"]
        raise Error.new("Necesitas permisos de escritura en un repositorio activo.", status: 403)
      end
      canonical
    end

    def self.client_for(repository)
      token = scoped_token(repository)
      Github::Client.new(token: token, authorized_repository_id: repository.github_id,
        token_refresher: -> { scoped_token(repository) })
    end

    def self.scoped_token(repository)
      canonical = repository_for(repository.user, installation_id: repository.installation_id, full_name: repository.full_name)
      unless canonical.fetch("id").to_s == repository.github_id.to_s
        raise Error.new("El repositorio conectado ya no corresponde al recurso autorizado.", status: 403)
      end
      Github::App.new.installation_token(repository.installation_id, repository_id: repository.github_id)
    end
    private_class_method :scoped_token

    def self.find_in_pages
      result = []
      1.upto(MAX_PAGES) do |page|
        entries = yield(page)
        result.concat(entries)
        return result if entries.size < 100
      end
      raise Error, "Hay demasiados recursos para verificar el acceso a GitHub."
    end
    private_class_method :find_in_pages
  end
end

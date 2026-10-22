module Admin
  class AccessGrantsController < BaseController
    def index
      @grants = paginate(search(GithubAccessGrant.order(:login, :id), :login))
      @signed_up_ids = User.where(github_id: @grants.map(&:github_id)).pluck(:github_id)
    end

    def create
      login = params[:login].to_s.strip.delete_prefix("@")
      profile = Github::Access.user_client(current_user).account(login)
      GithubAccessGrant.transaction do
        grant = GithubAccessGrant.create!(github_id: profile.fetch("id"), login: profile.fetch("login"))
        audit!("access.grant", "GitHub:#{grant.github_id}", { "login" => grant.login })
      end
      redirect_to admin_access_grants_path, notice: "@#{profile['login']} ya puede iniciar sesión."
    rescue Github::Error
      redirect_to admin_access_grants_path, alert: "No se ha podido verificar la cuenta personal en GitHub. Comprueba el nombre y tu conexión."
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      redirect_to admin_access_grants_path, alert: "Esa cuenta ya está autorizada o no es una cuenta válida. Tu cuenta tiene acceso permanente."
    end

    def destroy
      grant = GithubAccessGrant.find(params[:id])
      GithubAccessGrant.transaction do
        audit!("access.revoke", "GitHub:#{grant.github_id}", { "login" => grant.login })
        grant.destroy!
      end
      redirect_to admin_access_grants_path, notice: "Acceso retirado a @#{grant.login}. Sus sesiones quedan bloqueadas."
    end
  end
end

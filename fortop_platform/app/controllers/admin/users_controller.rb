module Admin
  class UsersController < BaseController
    def index
      @users = paginate(search(User.order(created_at: :desc, id: :desc), :login, :name))
      @allowed_ids = GithubAccessGrant.where(github_id: @users.map(&:github_id)).pluck(:github_id)
    end

    def show
      @user = User.find(params[:id])
      @overview = Overview.new(user: @user)
      @repositories = @user.repositories.order(created_at: :desc).limit(20)
      @brands = @user.brands.order(created_at: :desc).limit(20)
      @recent = ExecutionCatalog.recent(user: @user, limit: 10)
      @grant = GithubAccessGrant.find_by(github_id: @user.github_id)
    end

    def destroy
      user = User.find(params[:id])
      raise OperationsError, "Tu cuenta de administrador no se puede eliminar." if user.admin?
      user.with_lock do
        user.repositories.order(:id).lock.load
        user.brands.order(:id).lock.load
        overview = Overview.new(user: user)
        if overview.active_count.positive?
          raise OperationsError, "Cancela o termina sus ejecuciones antes de eliminar la cuenta."
        end
        GithubAccessGrant.where(github_id: user.github_id).destroy_all
        audit!("user.delete", "User:#{user.id}", { "login" => user.login, "github_id" => user.github_id })
        user.destroy!
      end
      redirect_to admin_users_path, notice: "Cuenta y datos locales eliminados. Se ha retirado su acceso."
    rescue OperationsError, ActiveRecord::RecordNotDestroyed => error
      redirect_to admin_user_path(user), alert: error.message
    end
  end
end

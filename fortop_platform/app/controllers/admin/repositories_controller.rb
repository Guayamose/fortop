module Admin
  class RepositoriesController < BaseController
    def index
      @repositories = paginate(search(Repository.includes(:user).order(created_at: :desc, id: :desc), :full_name))
    end

    def show
      @repository = Repository.includes(:user).find(params[:id])
      @executions = paginate(@repository.scans.order(created_at: :desc, id: :desc))
    end

    def destroy
      repository = Repository.find(params[:id])
      repository.with_lock do
        audit!("repository.disconnect", "Repository:#{repository.id}", { "name" => repository.full_name })
        repository.destroy!
      end
      redirect_to admin_repositories_path, notice: "Repositorio desconectado y análisis locales eliminados."
    rescue ActiveRecord::RecordNotDestroyed
      redirect_to admin_repository_path(repository), alert: "Cancela o termina el análisis antes de desconectar el repositorio."
    end
  end
end

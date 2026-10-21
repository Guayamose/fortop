class RepositoriesController < ApplicationController
  before_action :set_repository, only: %i[show destroy]

  def index
    @brand_count = current_user.brands.count
    @repositories = current_user.repositories.includes(:scans).order(connected_at: :desc)
    @latest_scans = @repositories.to_h { |repository| [ repository.id, repository.scans.max_by { |scan| [ scan.created_at, scan.id ] } ] }
    @finding_counts = Finding.where(scan_id: @latest_scans.values.compact.map(&:id)).group(:scan_id).count
  end

  def new
    @page = [ params[:page].to_i, 1 ].max
    @installations = github_client.installations(per_page: 100)
    @installation = @installations.find { |item| item.fetch("id").to_s == params[:installation_id].to_s } || @installations.first
    @github_repositories = @installation ? github_client.installation_repositories(@installation.fetch("id"), page: @page, per_page: 30) : []
    @has_next_page = @github_repositories.length == 30
    @connected_ids = current_user.repositories.pluck(:github_id)
    @query = params[:q].to_s.strip
    if @query.present?
      @github_repositories = @github_repositories.select { |repo| repo.fetch("full_name").downcase.include?(@query.downcase) }
    end
  rescue Github::Error => error
    redirect_to repositories_path, alert: github_error_message(error)
  end

  def create
    installation_id = params.require(:installation_id).to_i
    full_name = params.require(:full_name).to_s
    canonical = Github::Access.repository_for(current_user, installation_id: installation_id, full_name: full_name)
    unless canonical && canonical.dig("permissions", "push") && !canonical["archived"] && !canonical["disabled"]
      redirect_to new_repository_path(installation_id: installation_id), alert: "Elige un repositorio activo en el que tengas permisos de escritura."
      return
    end

    repository = current_user.repositories.find_or_initialize_by(github_id: canonical.fetch("id"))
    repository.update!(full_name: canonical.fetch("full_name"), description: canonical["description"],
      default_branch: canonical.fetch("default_branch"), html_url: canonical.fetch("html_url"),
      language: canonical["language"], private: canonical.fetch("private"), installation_id: installation_id)
    redirect_to repository_path(repository), notice: "Repositorio conectado. Ya puedes iniciar su primer análisis."
  rescue Github::Error => error
    redirect_to new_repository_path, alert: github_error_message(error)
  rescue ActiveRecord::RecordInvalid => error
    redirect_to new_repository_path, alert: error.record.errors.full_messages.to_sentence
  rescue ActiveRecord::RecordNotUnique
    redirect_to repositories_path, notice: "El repositorio ya está conectado."
  end

  def show
    @repository.scans.active.each(&:expire_if_stale!)
    @scans = @repository.scans.recent
    @latest_scan = @scans.first
    @active_scan = @scans.find(&:active?)
    if params[:scan_id].present?
      raise ActiveRecord::RecordNotFound unless params[:scan_id].is_a?(String) && params[:scan_id].match?(/\A[1-9]\d*\z/)
      @selected_scan = @scans.find(params[:scan_id])
      if request.format.json? && params[:follow_restart] == "1"
        # A live workspace follows its replacement. Explicit history navigation
        # continues to show the requested scan, including cancelled executions.
        while (next_id = @selected_scan.metadata["restart_scan_id"]) && next_id.to_i > @selected_scan.id
          @selected_scan = @scans.find(next_id)
        end
      end
    else
      @selected_scan = @active_scan || @latest_scan
    end
    @finding_counts = Finding.where(scan_id: @scans.map(&:id)).group(:scan_id).count

    respond_to do |format|
      format.html
      format.json do
        render json: { html: render_to_string(partial: "repositories/workspace", formats: [ :html ]), active: @active_scan.present? }
      end
    end
  end

  def destroy
    if @repository.destroy
      redirect_to repositories_path, notice: "Repositorio desconectado de Fortop."
    else
      redirect_to repository_path(@repository), alert: @repository.errors.full_messages.to_sentence
    end
  end

  private

  def set_repository
    @repository = current_user.repositories.find(params[:id])
  end

  def github_client
    @github_client ||= Github::Access.user_client(current_user)
  end

  def github_error_message(error)
    if [ 401, 403 ].include?(error.status)
      "GitHub no ha autorizado esta acción. Revisa el acceso de Fortop a tu cuenta y sus repositorios."
    else
      "No se ha podido consultar GitHub. Vuelve a intentarlo en unos instantes."
    end
  end
end

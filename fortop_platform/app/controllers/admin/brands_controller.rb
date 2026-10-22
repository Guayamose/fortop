module Admin
  class BrandsController < BaseController
    def index
      @brands = paginate(search(Brand.includes(:user).order(created_at: :desc, id: :desc), :name, :website))
    end

    def show
      @brand = Brand.includes(:user).find(params[:id])
      @executions = paginate(@brand.visibility_studies.order(created_at: :desc, id: :desc))
    end

    def destroy
      brand = Brand.find(params[:id])
      brand.with_lock do
        audit!("brand.delete", "Brand:#{brand.id}", { "name" => brand.name })
        brand.destroy!
      end
      redirect_to admin_brands_path, notice: "Marca y estudios locales eliminados."
    rescue ActiveRecord::RecordNotDestroyed
      redirect_to admin_brand_path(brand), alert: "Cancela o termina el estudio antes de eliminar la marca."
    end
  end
end

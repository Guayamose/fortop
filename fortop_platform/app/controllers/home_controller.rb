class HomeController < ApplicationController
  def index
    @repository_count = current_user.repositories.count
    @brand_count = current_user.brands.count
  end
end

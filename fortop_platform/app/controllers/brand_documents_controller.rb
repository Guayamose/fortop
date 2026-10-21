class BrandDocumentsController < ApplicationController
  def show
    document = current_user.brand_documents.find(params[:id])
    response.headers["Cache-Control"] = "private, no-store"
    send_data document.file.download, filename: document.file.filename.to_s, type: "application/octet-stream", disposition: "attachment"
  end
end

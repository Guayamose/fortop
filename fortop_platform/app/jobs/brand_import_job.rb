class BrandImportJob < ApplicationJob
  queue_as :default

  def perform(import_id)
    import = BrandImport.find_by(id: import_id)
    BrandImports::Processor.new(import).call if import&.queued?
  end
end

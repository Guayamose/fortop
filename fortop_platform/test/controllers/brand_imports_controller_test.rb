require "test_helper"
require_relative "../support/github_sign_in"
require_relative "../support/visibility_fixtures"

class BrandImportsControllerTest < ActionDispatch::IntegrationTest
  include GithubSignIn
  include VisibilityFixtures
  include ActiveJob::TestHelper

  setup { @user = sign_in_github }

  test "uploads queue a single private interpretation and completed files attach to a saved brand" do
    assert_enqueued_with(job: BrandImportJob) do
      post brand_imports_path, params: { files: [ upload ], fields: { name: "Nébula" } }
    end
    assert_response :accepted
    import = @user.brand_imports.last
    assert_equal "queued", response.parsed_body["status"]
    BrandImports::Processor.new(import, client: FakeVisibilityClient.new).call
    get brand_import_path(import)
    assert_equal "Nébula", response.parsed_body.dig("fields", "name")
    document = import.documents.sole
    post brands_path, params: { brand: import.result["fields"].merge("brief" => "x", "document_ids" => [ document.id ]) }
    assert_response :unprocessable_entity
    assert_select ".brand-document input[value=?]", document.id.to_s
    post brands_path, params: { brand: import.result["fields"].merge("document_ids" => [ document.id ]) }
    assert_response :redirect
    brand = @user.brands.last
    assert_equal [ document.id ], brand.current_brief.documents.ids
    get brand_document_path(document)
    assert_response :success
    assert_equal document.file.download, response.body
    assert_includes response.headers["Content-Disposition"], "attachment"
    assert_includes response.headers["Cache-Control"], "private"
    get edit_brand_path(brand)
    assert_select ".brand-document input[value=?]", document.id.to_s
    study = complete_visibility(visibility_study(brand: brand))
    get brand_path(brand, study_id: study.id)
    assert_select "#study-brief .brand-source-document summary", text: /brief.txt/
    assert_select "#study-brief .brand-source-document .visibility-original-text", text: /Nébula ofrece facturación/
    patch brand_path(brand), params: { brand: { document_ids: [ "" ] } }
    assert_empty brand.reload.documents
    assert_equal [ document.id ], brand.brand_briefs.order(:version).first.documents.ids
  end

  test "foreign documents imports and incomplete uploads are never readable or attachable" do
    foreign = visibility_brand
    import = foreign.user.brand_imports.create!(status: "completed")
    document = import.documents.create!
    document.file.attach(io: StringIO.new("Private competitor strategy."), filename: "private.txt", identify: false)
    get brand_import_path(import)
    assert_response :not_found
    get brand_document_path(document)
    assert_response :not_found
    post retry_brand_import_path(import)
    assert_response :not_found
    brand = visibility_brand(user: @user)
    assert_no_difference("BrandBrief.count") do
      patch brand_path(brand), params: { brand: { document_ids: [ document.id ] } }
    end
    assert_response :not_found
    own = @user.brand_imports.create!
    incomplete = own.documents.create!
    assert_no_difference("BrandBrief.count") do
      patch brand_path(brand), params: { brand: { document_ids: [ incomplete.id ] } }
    end
    assert_response :not_found
  end

  test "rejects unsupported uploads without starting paid work and retries only eligible owner imports" do
    assert_no_enqueued_jobs(only: BrandImportJob) { post brand_imports_path, params: { files: [ upload(name: "payload.exe") ] } }
    assert_response :unprocessable_entity
    assert_no_difference("BrandImport.count") { post brand_imports_path, params: { files: [] } }
    assert_response :unprocessable_entity
    import = @user.brand_imports.create!(status: "failed", retryable: true)
    assert_enqueued_with(job: BrandImportJob, args: [ import.id ]) { post retry_brand_import_path(import) }
    assert import.reload.queued?
    assert_no_enqueued_jobs(only: BrandImportJob) { post retry_brand_import_path(import) }
    assert_response :unprocessable_entity
  end

  private

  def upload(name: "brief.txt")
    file = Tempfile.new("brand-upload")
    file.write("Nébula ofrece facturación sencilla para pymes de España. https://nebula.com")
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "text/plain", original_filename: name)
  end
end

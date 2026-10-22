require "test_helper"
require_relative "../support/github_sign_in"
require_relative "../support/visibility_fixtures"

class AdminControllerTest < ActionDispatch::IntegrationTest
  include GithubSignIn
  include VisibilityFixtures
  include ActiveJob::TestHelper

  setup do
    @other = User.from_github({ "id" => 701, "login" => "another-builder" }, token: "ghu_other_private_token")
    GithubAccessGrant.create!(github_id: @other.github_id, login: @other.login)
    @repository = connected_repository(@other)
    @scan = @repository.scans.create!(status: "completed", metadata: { "usage" => { "requests" => 2, "total_tokens" => 850 } }, summary: "Cambios listos para revisar.")
    @brand = visibility_brand(user: @other)
    @study = visibility_study(brand: @brand)
    @study.update!(status: "failed", spent_usd: "0.25", request_count: 2, token_count: 420, error_message: "Presupuesto agotado.")
    @import = @other.brand_imports.create!(status: "failed", retryable: true, spent_usd: "0.05", usage: { "total_tokens" => 100 })
  end

  test "all admin GET routes require authentication and reject an authorized non-owner even with the owner's handle" do
    read_routes.each do |path|
      get path
      assert_redirected_to new_session_path, path
    end
    sign_in_github(login: "Guayamose")
    read_routes.each do |path|
      get path
      assert_response :not_found, path
    end
    get root_path
    assert_select 'a[href="/admin"]', count: 0
  end

  test "non-owner cannot mutate access settings data or executions" do
    sign_in_github
    grant = GithubAccessGrant.find_by!(github_id: @other.github_id)
    assert_no_difference [ "GithubAccessGrant.count", "PlatformSetting.count", "AdminAuditEvent.count", "User.count", "Repository.count", "Brand.count" ] do
      [ [ :post, admin_access_grants_path, { login: "someone" } ],
        [ :delete, admin_access_grant_path(grant), {} ],
        [ :patch, admin_settings_path, { settings: { "NEW_WORK_ENABLED" => "false" } } ],
        [ :delete, admin_settings_path, {} ], [ :delete, admin_user_path(@other), {} ],
        [ :delete, admin_repository_path(@repository), {} ], [ :delete, admin_brand_path(@brand), {} ],
        [ :post, admin_control_activity_entry_path(kind: "studies", id: @study.id), { operation: "retry" } ] ].each do |method, path, values|
        public_send(method, path, params: values)
        assert_response :not_found, path
      end
    end
    assert @study.reload.failed?
  end

  test "owner can inspect every administrative section across user boundaries without exposing credentials" do
    owner = sign_in_owner
    refute_equal User::OWNER_GITHUB_ID, owner.id
    read_routes.each do |path|
      get path
      assert_response :success, path
      assert_equal "no-store", response.headers["Cache-Control"], path
      assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"], path
      refute_includes response.body, "ghu_other_private_token"
      refute_includes response.body, "ghr_test_only"
      assert_select 'meta[name="turbo-cache-control"][content="no-cache"]'
    end
    get root_path
    assert_select 'a[href="/admin"]', text: "Administración"
    get repository_path(@repository)
    assert_response :not_found # Administrative access never impersonates the owner.
  end

  test "grant resolves a real GitHub identity on the server and revoke blocks existing sessions" do
    sign_in_owner
    client = Object.new
    client.define_singleton_method(:account) { |login| raise "Wrong login" unless login == "new-user"; { "id" => 7788, "login" => "New-User" } }
    Github::Access.stub(:user_client, client) do
      assert_difference [ "GithubAccessGrant.count", "AdminAuditEvent.count" ], 1 do
        post admin_access_grants_path, params: { login: "@new-user", github_id: User::OWNER_GITHUB_ID, admin: true }
      end
    end
    grant = GithubAccessGrant.find_by!(github_id: 7788)
    assert_equal "New-User", grant.login
    visitor = open_session
    visitor.extend(GithubSignIn)
    user = visitor.sign_in_github(id: 7788, login: "renamed-user", authorized: false)
    assert_equal 7788, user.github_id
    visitor.get repositories_path
    visitor.assert_response :success
    delete admin_access_grant_path(grant)
    assert_redirected_to admin_access_grants_path
    assert User.exists?(user.id)
    visitor.get repositories_path
    visitor.assert_redirected_to new_session_path
    assert_nil visitor.session[:user_id]
    visitor.get brand_import_path(@import)
    visitor.assert_redirected_to new_session_path
    assert_equal %w[access.grant access.revoke], AdminAuditEvent.order(:id).pluck(:action)
  end

  test "unknown accounts cannot sign in or persist their GitHub tokens" do
    assert_no_difference "User.count" do
      assert_nil sign_in_github(id: 99999, login: "Guayamose", authorized: false)
    end
    assert_redirected_to new_session_path
    assert_match "no tiene acceso", flash[:alert]
    assert_nil session[:user_id]
  end

  test "owner remains authorized after rename and never needs a grant" do
    sign_in_github(id: User::OWNER_GITHUB_ID, login: "owner-renamed", authorized: false)
    get admin_root_path
    assert_response :success
    assert_select ".admin-private", text: /owner-renamed/
    assert_no_difference "User.count" do
      delete admin_user_path(User.find_by!(github_id: User::OWNER_GITHUB_ID))
    end
    assert_match "no se puede eliminar", flash[:alert]
    refute GithubAccessGrant.new(github_id: User::OWNER_GITHUB_ID, login: "Guayamose").valid?
  end

  test "settings validate atomically and control new jobs while leaving pause and cancellation available" do
    sign_in_owner
    assert_no_difference [ "PlatformSetting.count", "AdminAuditEvent.count" ] do
      patch admin_settings_path, params: { settings: { "AGENT_MAX_TOTAL_TOKENS" => "20000", "VISIBILITY_DAILY_BUDGET_USD" => "-1" } }
    end
    assert flash[:alert].present?
    patch admin_settings_path, params: { settings: { "NEW_WORK_ENABLED" => "false", "AGENT_MAX_TOTAL_TOKENS" => "20000", "GITHUB_CLIENT_SECRET" => "do-not-store" } }
    assert_redirected_to admin_settings_path
    assert_equal "20000", PlatformSetting.fetch("AGENT_MAX_TOTAL_TOKENS")
    refute PlatformSetting.exists?(key: "GITHUB_CLIENT_SECRET")
    assert_no_enqueued_jobs do
      post admin_control_activity_entry_path(kind: "studies", id: @study.id), params: { operation: "retry" }
    end
    assert_match "pausadas", flash[:alert]
    other_session = open_session
    other_session.extend(GithubSignIn)
    other_session.sign_in_github(id: @other.github_id, login: @other.login)
    assert_no_difference "Scan.count" do
      other_session.post repository_scans_path(@repository)
    end
    assert_no_difference "VisibilityStudy.count" do
      other_session.post brand_visibility_studies_path(@brand)
    end
    assert_no_difference "BrandImport.count" do
      other_session.post brand_imports_path
      other_session.assert_response :service_unavailable
    end
    active = @repository.scans.create!
    assert_enqueued_with(job: ScanJob, args: [ active.id ]) do
      post admin_control_activity_entry_path(kind: "scans", id: active.id), params: { operation: "pause" }
    end
    assert_equal "pause", active.reload.control_action
    delete admin_settings_path
    assert_empty PlatformSetting.all
    assert PlatformSetting.new_work_enabled?
  end

  test "admin can recover scans studies and imports with their existing job and budget rules" do
    sign_in_owner
    paused = @repository.scans.create!(status: "paused")
    assert_enqueued_with(job: ScanJob, args: [ paused.id ]) do
      post admin_control_activity_entry_path(kind: "scans", id: paused.id), params: { operation: "resume" }
    end
    assert paused.reload.queued?
    paused.update!(status: "cancelled")
    assert_difference "Scan.count", 1 do
      assert_enqueued_with(job: ScanJob) do
        post admin_control_activity_entry_path(kind: "scans", id: @scan.id), params: { operation: "restart" }
      end
    end
    assert_enqueued_with(job: VisibilityStudyJob, args: [ @study.id ]) do
      post admin_control_activity_entry_path(kind: "studies", id: @study.id), params: { operation: "retry", budget_usd: "4" }
    end
    assert @study.reload.queued?
    assert_equal BigDecimal("4"), @study.budget_usd
    assert_enqueued_with(job: BrandImportJob, args: [ @import.id ]) do
      post admin_control_activity_entry_path(kind: "imports", id: @import.id), params: { operation: "retry" }
    end
    assert @import.reload.queued?
    assert_equal 4, AdminAuditEvent.count
    @import.update!(status: "failed", retryable: true, request_count: 3)
    assert_no_enqueued_jobs do
      post admin_control_activity_entry_path(kind: "imports", id: @import.id), params: { operation: "retry" }
    end
    assert flash[:alert].present?
  end

  test "data deletion is audited and refuses active work" do
    sign_in_owner
    active = @repository.scans.create!
    assert_no_difference [ "User.count", "Repository.count", "AdminAuditEvent.count" ] do
      delete admin_user_path(@other)
      delete admin_repository_path(@repository)
    end
    active.update!(status: "cancelled")
    assert_difference "Repository.count", -1 do
      delete admin_repository_path(@repository)
    end
    assert_difference "Brand.count", -1 do
      delete admin_brand_path(@brand)
    end
    assert_difference "User.count", -1 do
      delete admin_user_path(@other)
    end
    refute GithubAccessGrant.exists?(github_id: @other.github_id)
    assert_equal %w[repository.disconnect brand.delete user.delete], AdminAuditEvent.order(:id).pluck(:action)
  end

  test "catalog rejects arbitrary model names and mutations require CSRF" do
    sign_in_owner
    get admin_activity_entry_path(kind: "User", id: @other.id)
    assert_response :not_found
    post admin_control_activity_entry_path(kind: "scans", id: @scan.id), params: { operation: "destroy" }
    assert_response :unprocessable_entity
    old = ApplicationController.allow_forgery_protection
    begin
      ApplicationController.allow_forgery_protection = true
      assert_no_difference "GithubAccessGrant.count" do
        delete admin_access_grant_path(GithubAccessGrant.find_by!(github_id: @other.github_id))
      end
      assert_response :unprocessable_content
    ensure
      ApplicationController.allow_forgery_protection = old
    end
  end

  test "user search escapes SQL wildcard characters and pagination remains bounded" do
    sign_in_owner
    get admin_users_path, params: { q: "%" }
    assert_response :success
    assert_select ".admin-table tbody tr", count: 0
    get admin_users_path, params: { q: "another-builder", page: "9999999999" }
    assert_select ".admin-record-link", text: "@another-builder"
    assert_select ".admin-pagination", text: /Página 1 de 1/
    get admin_activity_path, params: { kind: "studies", state: "failed" }
    assert_select ".admin-record-link", text: @brand.name
    get admin_activity_entry_path(kind: "studies", id: @study.id)
    assert_select ".admin-error", text: "Presupuesto agotado."
  end

  private

  def sign_in_owner
    sign_in_github(id: User::OWNER_GITHUB_ID, login: "Guayamose", authorized: false)
  end

  def read_routes
    [ admin_root_path, admin_access_grants_path, admin_users_path, admin_user_path(@other),
      admin_repositories_path, admin_repository_path(@repository), admin_brands_path, admin_brand_path(@brand),
      admin_activity_path, admin_activity_entry_path(kind: "scans", id: @scan.id),
      admin_activity_entry_path(kind: "studies", id: @study.id), admin_activity_entry_path(kind: "imports", id: @import.id),
      admin_settings_path, admin_audit_events_path ]
  end
end

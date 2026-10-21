require "test_helper"

class Github::AppSetupControllerTest < ActionDispatch::IntegrationTest
  test "setup is not reachable outside development" do
    get github_setup_path
    assert_response :not_found
  end

  test "setup rejects nonlocal clients even in development" do
    Rails.env.stub(:development?, true) do
      get github_setup_path, env: { "REMOTE_ADDR" => "203.0.113.5" }
    end
    assert_response :not_found
  end

  test "forwarded loopback header cannot turn a remote socket into local setup access" do
    Rails.env.stub(:development?, true) do
      get github_setup_path, env: { "REMOTE_ADDR" => "203.0.113.5", "HTTP_X_FORWARDED_FOR" => "127.0.0.1" }
    end
    assert_response :not_found
  end

  test "local setup renders a public manifest and verifies callback state" do
    manifest = Minitest::Mock.new
    manifest.expect :manifest, { name: "Fortop-test", default_permissions: { contents: "write" } }
    manifest.expect :register!, true, [], code: "a" * 40
    Rails.env.stub(:development?, true) do
      Github::App.stub(:configured?, false) do
        Github::AppManifest.stub(:new, manifest) do
          get github_setup_path, env: { "REMOTE_ADDR" => "127.0.0.1" }
          assert_response :success
          form = Nokogiri::HTML(response.body).at_css('form[action^="https://github.com/settings/apps/new"]')
          assert form
          state = URI.decode_www_form(URI(form["action"]).query).to_h.fetch("state")
          assert_equal 64, state.bytesize
          assert_no_difference("User.count") do
            get github_manifest_callback_path, params: { state: state, code: "a" * 40 }, env: { "REMOTE_ADDR" => "127.0.0.1" }
          end
          assert_redirected_to new_session_path
        end
      end
    end
    manifest.verify
  end

  test "setup callback cannot exchange a code without its original session" do
    Github::AppManifest.stub(:new, -> { flunk "unexpected manifest conversion" }) do
      Rails.env.stub(:development?, true) do
        get github_manifest_callback_path, params: { state: "a" * 64, code: "a" * 40 }, env: { "REMOTE_ADDR" => "127.0.0.1" }
      end
    end
    assert_redirected_to new_session_path
  end

  test "setup manifest handshake expires after fifteen minutes" do
    manifest = Minitest::Mock.new
    manifest.expect :manifest, { name: "Fortop-test" }
    Rails.env.stub(:development?, true) do
      Github::App.stub(:configured?, false) do
        Github::AppManifest.stub(:new, manifest) do
          get github_setup_path, env: { "REMOTE_ADDR" => "127.0.0.1" }
          state = session[:github_manifest]["state"]
          travel 16.minutes do
            get github_manifest_callback_path, params: { state: state, code: "a" * 40 }, env: { "REMOTE_ADDR" => "127.0.0.1" }
          end
          assert_redirected_to new_session_path
          assert_match "caducado", flash[:alert]
        end
      end
    end
    manifest.verify
  end
end

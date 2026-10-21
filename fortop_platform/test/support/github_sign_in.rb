module GithubSignIn
  def sign_in_github(id: 90001, login: "fortop-builder")
    oauth = Object.new
    state_value = nil
    oauth.define_singleton_method(:authorize_url) do |state:, code_verifier:|
      state_value = state
      "https://github.com/login/oauth/authorize?state=#{state}"
    end
    oauth.define_singleton_method(:exchange) { |**| { token: "ghu_test_only", refresh_token: "ghr_test_only", expires_at: 8.hours.from_now } }
    client = Object.new
    client.define_singleton_method(:user) { { "id" => id, "login" => login, "name" => "Fortop Builder" } }
    Github::OAuth.stub(:new, oauth) do
      Github::Client.stub(:new, client) do
        post session_path
        get callback_session_path, params: { code: "test-code", state: state_value }
      end
    end
    User.find_by!(github_id: id)
  end

  def connected_repository(user, github_id: 101, name: "fortop-builder/site")
    user.repositories.create!(github_id: github_id, installation_id: 5001,
      full_name: name, default_branch: "main", html_url: "https://github.com/#{name}", language: "Ruby")
  end

  def github_repository(id: 101, full_name: "fortop-builder/site", **attributes)
    { "id" => id, "full_name" => full_name, "default_branch" => "main", "html_url" => "https://github.com/#{full_name}",
      "private" => true, "language" => "Ruby", "permissions" => { "push" => true }, "archived" => false, "disabled" => false }.merge(attributes.stringify_keys)
  end
end

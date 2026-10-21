require "test_helper"
require_relative "../support/github_sign_in"

class HomeControllerTest < ActionDispatch::IntegrationTest
  include GithubSignIn

  test "home requires authentication" do
    get root_path
    assert_redirected_to new_session_path
  end

  test "sign in opens a distinct home with navigation to repositories and brands" do
    user = sign_in_github
    assert_redirected_to root_path
    assert_nil flash[:notice]
    connected_repository(user)
    get root_path
    assert_response :success
    assert_select "h1", "Te damos la bienvenida"
    assert_select ".welcome-account", text: /1 repositorio/
    assert_select "a[aria-current=page]", text: "Inicio", count: 1
    assert_select ".welcome-actions a[href=?]", repositories_path, text: "Analizar un repositorio"
    assert_select ".repository-browser, .repository-card, .empty-state", count: 0

    get repositories_path
    assert_response :success
    assert_select "h1", "Repositorios"
    assert_select "a[aria-current=page]", text: "Repositorios", count: 1
    assert_select ".workspace-welcome", count: 0
    assert_select ".repository-card", count: 1

    get new_session_path
    assert_redirected_to root_path
  end
end

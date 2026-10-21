require "test_helper"
require "tmpdir"

class Github::ConfigurationTest < ActiveSupport::TestCase
  test "local worker loads newly registered GitHub keys without reading provider credentials into configuration" do
    Dir.mktmpdir do |directory|
      path = Pathname(directory).join(".env")
      path.write("GITHUB_CLIENT_ID=Iv1.new\nGITHUB_CLIENT_SECRET=new-secret\nFORTOP_TEST_OTHER_KEY=do-not-load\n")
      inherited = { "GITHUB_CLIENT_ID" => "placeholder", "APP_URL" => "http://localhost:3000" }
      result = Github::Configuration.local_environment(inherited: inherited, path: path)
      assert_equal "Iv1.new", result["GITHUB_CLIENT_ID"]
      assert_equal "new-secret", result["GITHUB_CLIENT_SECRET"]
      assert_equal "http://localhost:3000", result["APP_URL"]
      refute result.key?("FORTOP_TEST_OTHER_KEY")
      assert_equal "placeholder", inherited["GITHUB_CLIENT_ID"]
    end
  end

  test "empty local placeholders cannot replace valid inherited credentials" do
    Dir.mktmpdir do |directory|
      path = Pathname(directory).join(".env")
      path.write("GITHUB_CLIENT_ID=\n")
      result = Github::Configuration.local_environment(inherited: { "GITHUB_CLIENT_ID" => "Iv1.valid" }, path: path)
      assert_equal "Iv1.valid", result["GITHUB_CLIENT_ID"]
    end
  end

  test "production and tests do not inspect local environment files" do
    Github::Configuration.stub(:local_environment, ->(**_args) { flunk "unexpected local configuration read" }) do
      Rails.env.stub(:development?, false) { assert_kind_of Hash, Github::Configuration.environment }
    end
  end
end

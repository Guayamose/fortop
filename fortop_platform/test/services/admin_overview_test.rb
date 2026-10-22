require "test_helper"
require_relative "../support/visibility_fixtures"

class AdminOverviewTest < ActiveSupport::TestCase
  include VisibilityFixtures

  test "usage is scoped by user and does not count visibility calls twice" do
    brand = visibility_brand
    study = visibility_study(brand: brand)
    study.update!(spent_usd: "0.25", request_count: 2, token_count: 300)
    study.visibility_calls.create!(task_key: "reserved", model: "gemini-3.5-flash-lite", status: "uncertain", cost_usd: "0.25")
    brand.user.brand_imports.create!(spent_usd: "0.05", request_count: 1, usage: { "total_tokens" => 90 })
    repository = brand.user.repositories.create!(github_id: 73, full_name: "builder/site", html_url: "https://github.com/builder/site", default_branch: "main")
    repository.scans.create!(status: "completed", metadata: { "usage" => { "total_tokens" => 400, "requests" => 3 } })
    repository.scans.create!(status: "failed", metadata: { "usage" => { "total_tokens" => "bad-provider-data" } })
    overview = Admin::Overview.new(user: brand.user)
    assert_equal BigDecimal("0.3"), overview.estimated_spend
    assert_equal [ 400, 300, 90 ], overview.usage.pluck(:tokens)
    assert_equal [ 3, 2, 1 ], overview.usage.pluck(:requests)
    overview.usage.each { |row| assert_instance_of Integer, row.fetch(:tokens) }
    other = visibility_brand.user
    assert_equal 0, Admin::Overview.new(user: other).estimated_spend
    assert_equal [ 0, 0, 0 ], Admin::Overview.new(user: other).usage.pluck(:tokens)
  end
end

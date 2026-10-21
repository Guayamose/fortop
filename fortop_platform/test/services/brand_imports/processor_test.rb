require "test_helper"
require_relative "../../support/visibility_fixtures"

class BrandImportProcessorTest < ActiveSupport::TestCase
  include VisibilityFixtures

  setup do
    @brand = visibility_brand
    @import = @brand.user.brand_imports.create!(input_fields: { "name" => "Nébula" })
    @document = @import.documents.create!
    @document.file.attach(io: StringIO.new("Nébula ofrece facturación para pymes de España. https://nebula.com. Su competidor es Contalia."), filename: "brief.txt", identify: false)
    @client = VisibilityFixtures::FakeVisibilityClient.new
  end

  test "extracts and persists private context and a structured brief with exactly one ungrounded request" do
    BrandImports::Processor.new(@import, client: @client).call
    assert @import.reload.completed?, @import.error_message
    assert_equal "Nébula", @import.result.dig("fields", "name")
    assert_includes @document.reload.extracted_text, "pymes de España"
    assert_equal 1, @client.requests.size
    assert_equal false, @client.requests.first[:grounded]
    assert_includes @client.requests.first[:prompt], "https://nebula.com"
    assert_equal 1, @import.request_count
    assert_operator @import.spent_usd, :>, 0
    BrandImports::Processor.new(@import, client: @client).call
    assert_equal 1, @client.requests.size
    raw = BrandDocument.connection.select_value("SELECT extracted_text FROM brand_documents WHERE id=#{@document.id}")
    assert_no_match(/pymes/, raw)
    assert_not @document.update(extracted_text: "Cannot replace a completed source")
  end

  test "document-only edits create immutable brief versions and studies receive their original documents" do
    BrandImports::Processor.new(@import, client: @client).call
    @document.reload
    old = @brand.current_brief
    @brand.update!(document_ids: [ @document.id ])
    current = @brand.current_brief
    assert_not_equal old.id, current.id
    assert_empty old.documents
    assert_equal [ @document.id ], current.documents.ids
    study = visibility_study(brand: @brand)
    @brand.update!(document_ids: [])
    assert_empty @brand.reload.documents
    assert_equal [ @document.id ], study.reload.brand_brief.documents.ids
    client = VisibilityFixtures::FakeVisibilityClient.new
    complete_visibility(study, client: client)
    interpretation = client.requests.find { |request| request[:schema]&.dig(:properties, "business") }
    diagnosis = client.requests.find { |request| request[:schema]&.dig(:properties, "insights") }
    assert_includes interpretation[:prompt], @document.extracted_text
    assert_includes diagnosis[:prompt], @document.extracted_text
    client.requests.select { |request| request[:grounded] && !request[:prompt].start_with?("Search the public web") }.each do |request|
      assert_not_includes request[:prompt], @document.extracted_text
    end
  end

  test "daily budget exhaustion stops before constructing a paid request" do
    @import.update!(spent_usd: BigDecimal(ENV.fetch("VISIBILITY_DAILY_BUDGET_USD", "10")))
    BrandImports::Processor.new(@import, client: @client).call
    assert @import.reload.failed?
    assert @import.retryable?
    assert_equal 0, @import.request_count
    assert_empty @client.requests
    assert_match(/presupuesto diario/, @import.error_message)
  end

  test "invalid structured output is rejected and a failed brand edit retains its document selection" do
    client = Object.new
    client.define_singleton_method(:generate) do |**|
      Visibility::GoogleClient::Result.new(text: '{"fields":{"name":"incomplete"},"warnings":[]}', citations: [], search_queries: [], search_entry_point: nil,
        usage: { "input_tokens" => 10, "output_tokens" => 10, "total_tokens" => 20, "search_queries" => 0 }, model_version: "fixture")
    end
    BrandImports::Processor.new(@import, client: client).call
    assert @import.reload.failed?
    assert @import.retryable?
    assert_nil @import.result
    @import.update!(status: "queued")
    BrandImports::Processor.new(@import, client: @client).call
    @brand.update!(document_ids: [ @document.id ])
    versions = @brand.brand_briefs.count
    assert_not @brand.update(brief: "x", document_ids: [])
    assert_equal [ @document.id ], @brand.reload.documents.ids
    assert_equal versions, @brand.brand_briefs.count
  end

  test "upstream failures retain cost reservations and extracted documents for an explicit retry" do
    @client.failure = Visibility::ProviderError.new("Temporal.", retryable: true)
    BrandImports::Processor.new(@import, client: @client).call
    assert @import.reload.failed?
    assert @import.retryable?
    assert @import.spent_usd.positive?
    assert @document.reload.extracted_text.present?
    first_cost = @import.spent_usd
    @import.update!(status: "queued")
    @client.failure = nil
    BrandImports::Processor.new(@import, client: @client).call
    assert @import.reload.completed?
    assert_operator @import.spent_usd, :>, first_cost
    assert_equal 2, @import.request_count
  end
end

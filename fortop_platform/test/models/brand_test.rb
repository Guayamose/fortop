require "test_helper"
require_relative "../support/visibility_fixtures"

class BrandTest < ActiveSupport::TestCase
  include VisibilityFixtures

  test "context versions are immutable and studies keep their original brief" do
    brand=visibility_brand
    original=brand.current_brief
    study=visibility_study(brand: brand)
    brand.update!(brief: "Ahora nos centramos en la facturación de pequeñas agencias y estudios de diseño.")
    assert_equal 2, brand.brand_briefs.count
    assert_equal original.id, study.reload.brand_brief_id
    assert_match(/pequeños negocios/, study.brand_brief.content)
    assert_not original.update(content: "No puede modificarse una versión guardada.")
    assert_equal "Ofrecemos", original.reload.content.split.first
    raw=Brand.connection.select_value("SELECT brief FROM brands WHERE id=#{brand.id}")
    assert_no_match(/facturación/, raw)
    assert_not brand.destroy
    study.update!(status: "cancelled")
    assert brand.destroy
  end

  test "markets and public domains are validated" do
    brand=visibility_brand
    brand.assign_attributes(website: "http://localhost", markets_text: "X | spanish")
    assert_not brand.valid?
    assert brand.errors[:website].present?
    assert brand.errors[:markets].present?
    brand.assign_attributes(website: "nebula.com", markets_text: "España | es\nReino Unido | en", aliases_text: "Nebula, Nébula\nNebula")
    assert brand.valid?
    assert_equal 2, brand.markets.size
    assert_equal [ "Nebula", "Nébula" ], brand.aliases
  end
end

require "test_helper"

class VisibilityHelperTest < ActionView::TestCase
  test "provider search suggestions are isolated and strip active markup and event handlers" do
    html='<div onclick="alert(1)"><script>alert(1)</script><iframe src="https://evil.com"></iframe><form action="https://evil.com"><input></form><a href="javascript:alert(1)">Unsafe</a><a href="https://www.google.com/search?q=software">Search</a><img src=x onerror="alert(1)"></div>'
    rendered=visibility_search_widget(html)
    document=Nokogiri::HTML.fragment(rendered)
    frame=document.at_css("iframe")
    assert_equal "allow-popups allow-popups-to-escape-sandbox", frame["sandbox"]
    assert_not_includes frame["sandbox"], "allow-same-origin"
    isolated=Nokogiri::HTML(frame["srcdoc"])
    assert_empty isolated.css("script,iframe,form,[onclick],[onerror]")
    assert_equal "", isolated.at_css("a")["href"]
    assert_equal "https://www.google.com/search?q=software", isolated.css("a").last["href"]
    assert_includes frame["srcdoc"], "default-src 'none'"
    assert_nil visibility_search_widget(nil)
  end
end

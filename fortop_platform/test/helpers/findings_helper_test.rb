require "test_helper"

class FindingsHelperTest < ActionView::TestCase
  include FindingsHelper

  test "highlights source without turning HTML evidence into executable markup" do
    finding = Finding.new(file_path: "index.html", evidence: "<script>alert('x')</script>\n<meta name=\"description\" content=\"Fortop\">")
    lines = highlighted_evidence(finding)
    assert_equal 2, lines.size
    html = Nokogiri::HTML.fragment(lines.join)
    assert_empty html.css("script, meta, img")
    assert html.css(".nt").any?
    assert_includes html.text, "<script>"
    assert_includes html.text, 'content="Fortop"'
  end

  test "multiline lexical state is retained and unknown formats remain readable" do
    finding = Finding.new(file_path: "page.js", evidence: "/* first\nsecond */\nconst title = 'Fortop';")
    lines = highlighted_evidence(finding)
    assert_equal 3, lines.size
    assert_includes lines[1], 'class="cm"'
    assert_equal "Plain Text", finding_lexer("ordinary text", "unknown.binary").title
  end

  test "diff rows distinguish additions deletions and source line numbers" do
    patch = "--- a/page.html\n+++ b/page.html\n@@ -5,2 +5,3 @@\n <head>\n-<title>Old</title>\n+<title>New</title>\n+<meta>\n"
    rows = finding_diff_rows(patch)
    assert_equal %w[hunk context deletion addition addition], rows.map { |row| row[:kind] }
    assert_equal [ 5, 6, nil, nil ], rows.drop(1).map { |row| row[:old] }
    assert_equal [ 5, nil, 6, 7 ], rows.drop(1).map { |row| row[:new] }
    assert_equal "<meta>", rows.last[:text]
  end

  test "only shows actual patches linked to this finding even when other findings share a path" do
    scan = Scan.new(changed_files: [ { "path" => "index.html", "finding_ids" => [ 12 ], "diff" => "real patch" },
      { "path" => "index.html", "finding_ids" => [ 13 ], "diff" => "another correction" } ])
    finding = Finding.new(id: 12, scan: scan)
    assert_equal [ "real patch" ], finding_changes(finding).map { |file| file["diff"] }
    finding.id = 99
    assert_empty finding_changes(finding)
  end
end

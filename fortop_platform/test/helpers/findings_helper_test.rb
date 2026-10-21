require "test_helper"

class FindingsHelperTest < ActionView::TestCase
  include FindingsHelper

  test "detects compound templates source aliases and language-specific filenames" do
    { "app/views/index.html.erb" => "erb", "app/layout.tsx" => "tsx", "page.mjs" => "javascript",
      "Gemfile" => "ruby", "main.py" => "python", "README.md" => "markdown", "Dockerfile" => "docker",
      "icon.svg" => "xml", "unknown.binary" => "text" }.each do |path, language|
      assert_equal language, finding_language(path).fetch("id"), path
    end
    assert_equal 242, FindingsHelper::LANGUAGES.size
  end

  test "source lines retain literal markup and whitespace for escaped view rendering" do
    source = "<script>alert('x')</script>\n  <meta name=\"description\" content=\"Fortop\">\n"
    lines = finding_evidence_lines(Finding.new(evidence: source))
    assert_equal 3, lines.size
    assert_equal source, lines.join("\n")
    assert_not lines.first.html_safe?
  end

  test "diff rows distinguish additions deletions and source line numbers without inserting markup" do
    patch = "--- a/page.html\n+++ b/page.html\n@@ -5,2 +5,3 @@\n <head>\n-<title>Old</title>\n+<title>New</title>\n+<meta>\n"
    rows = finding_diff_rows(patch)
    assert_equal %w[hunk context deletion addition addition], rows.map { |row| row[:kind] }
    assert_equal [ 5, 6, nil, nil ], rows.drop(1).map { |row| row[:old] }
    assert_equal [ 5, nil, 6, 7 ], rows.drop(1).map { |row| row[:new] }
    assert_equal "<meta>", rows.last[:text]
    assert_not rows.last[:text].html_safe?
  end

  test "diff retains separate hunk boundaries and exact whitespace" do
    patch = "@@ -1 +1 @@\n-  old\n+  new\n@@ -20 +20 @@\n-<script>x()</script>\n+<img src=x onerror=alert(1)>\n"
    rows = finding_diff_rows(patch)
    assert_equal 2, rows.count { |row| row[:kind] == "hunk" }
    assert_equal "  new", rows[2][:text]
    assert_equal 20, rows.last[:new]
    assert_equal "<img src=x onerror=alert(1)>", rows.last[:text]
    assert_not rows.last[:text].html_safe?
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

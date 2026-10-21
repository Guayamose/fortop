require "test_helper"

class Scans::CodeDiffTest < ActiveSupport::TestCase
  test "retains precise context and treats reordered repeated lines as actual changes" do
    result = Scans::CodeDiff.call(before: "one\ntwo\none\n", after: "one\none\ntwo\n", path: "page.txt")
    assert_equal 1, result["additions"]
    assert_equal 1, result["deletions"]
    assert_includes result["diff"], "--- a/page.txt\n+++ b/page.txt\n"
    assert_match(/\n-[^\n]+\n/, result["diff"])
    assert_match(/\n\+[^\n]+\n/, result["diff"])
  end

  test "merges overlapping context but keeps distant changes in separate hunks" do
    before = (1..30).map { |number| "line #{number}\n" }.join
    after = before.sub("line 2\n", "second\n").sub("line 4\n", "fourth\n").sub("line 25\n", "last\n")
    result = Scans::CodeDiff.call(before: before, after: after, path: "page.txt")
    assert_equal 2, result["diff"].scan(/^@@ /).size
    assert_equal 3, result["additions"]
    assert_equal 3, result["deletions"]
    assert_includes result["diff"], "+second"
    assert_includes result["diff"], "+fourth"
    assert_includes result["diff"], "+last"
  end

  test "represents a newly created file and preserves missing final newline markers" do
    result = Scans::CodeDiff.call(before: nil, after: "new content", path: "robots.txt")
    assert_includes result["diff"], "--- /dev/null"
    assert_includes result["diff"], "+new content"
    assert_includes result["diff"], "\\ No newline at end of file"
    assert_equal 1, result["additions"]
    assert_equal 0, result["deletions"]
  end

  test "does not invent a patch for identical content" do
    assert_equal({ "diff" => "", "additions" => 0, "deletions" => 0 }, Scans::CodeDiff.call(before: "same\n", after: "same\n", path: "page.txt"))
  end
end

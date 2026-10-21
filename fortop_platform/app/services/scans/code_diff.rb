require "diff/lcs"
require "diff/lcs/hunk"

module Scans
  class CodeDiff
    def self.call(before:, after:, path:)
      original, proposed = before.to_s.lines, after.to_s.lines
      pieces = Diff::LCS.diff(original, proposed)
      changes = pieces.flatten(1)
      hunks, offset = [], 0
      pieces.each do |piece|
        hunk = Diff::LCS::Hunk.new(original, proposed, piece, 3, offset)
        offset = hunk.file_length_difference
        hunk.merge(hunks.pop) if hunk.overlaps?(hunks.last)
        hunks << hunk
      end
      patch = hunks.each_with_index.map { |hunk, index| hunk.diff(:unified, index == hunks.size - 1).chomp }.join("\n")
      patch = "--- #{before.nil? ? '/dev/null' : "a/#{path}"}\n+++ b/#{path}\n#{patch}\n" if patch.present?
      { "diff" => patch, "additions" => changes.count { |change| change.action == "+" }, "deletions" => changes.count { |change| change.action == "-" } }
    end
  end
end

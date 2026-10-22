require "redcarpet"
require "nokogiri"

module Visibility
  # Compare visible text, not Markdown source. Keep wording, word boundaries,
  # negations and numbers intact; never use fuzzy similarity to prove a quote.
  class EvidenceText
    BLOCKS = %w[p div section article blockquote li ul ol h1 h2 h3 h4 h5 h6 pre table tr td th br hr].freeze
    attr_reader :text

    def initialize(source, plain: false)
      @text = normalize_layout(plain ? source.to_s : visible_text(source.to_s))
    end

    def find(quote, name: false)
      return unless quote.is_a?(String) && quote.length.between?(2, 6000)
      needle = self.class.new(quote).text
      return if needle.length < 2
      # A provider's short surface name may differ in case or accents. The
      # surrounding evidence still has to match; this does not resolve identity.
      haystack, offsets = comparison(name)
      needle = comparable(needle, name)
      pattern = Regexp.new("(?<![\\p{L}\\p{N}])#{Regexp.escape(needle)}(?![\\p{L}\\p{N}])", Regexp::IGNORECASE)
      match = pattern.match(haystack)
      return unless match
      text[offsets.fetch(match.begin(0))...offsets.fetch(match.end(0) - 1) + 1]
    end

    private

    def visible_text(source)
      markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML, tables: true, fenced_code_blocks: true, no_intra_emphasis: true)
      fragment = Nokogiri::HTML.fragment(markdown.render(source.gsub(/<!--.*?-->/m, "")))
      fragment.css("script, style, template, noscript, iframe, object, img, [hidden], [aria-hidden='true']").remove
      fragment.css("[style]").each do |node|
        node.remove if node["style"].match?(/(?:display\s*:\s*none|visibility\s*:\s*hidden)/i)
      end
      fragment.css(BLOCKS.join(",")).each do |node|
        node.add_previous_sibling(Nokogiri::XML::Text.new("\n", fragment.document))
        node.add_next_sibling(Nokogiri::XML::Text.new("\n", fragment.document))
      end
      fragment.text
    end

    def normalize_layout(text)
      text.unicode_normalize(:nfc).gsub(/[\u00ad\u200b\u200e\u200f\u202a-\u202e\u2066-\u2069\ufeff]/, "").gsub(/[[:space:]]+/, " ").strip
    end

    def comparable(text, name)
      value = text.unicode_normalize(:nfkc).tr("“”„«»", '"').tr("‘’ʼ", "'").tr("‐‑‒–—", "-")
      name ? value.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "") : value
    end

    def comparison(name)
      @comparisons ||= {}
      @comparisons[name] ||= begin
        offsets = []
        value = text.each_char.with_index.map do |char, index|
          normalized = comparable(char, name)
          normalized.length.times { offsets << index }
          normalized
        end.join
        [ value, offsets ]
      end
    end
  end
end

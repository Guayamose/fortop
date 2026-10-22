require "test_helper"

class VisibilityEvidenceTextTest < ActiveSupport::TestCase
  test "visible evidence survives Markdown HTML links tables and typography" do
    examples = [
      [ "* **Acciona Energía:** Ofrece contratos *on-site*.", "Acciona Energía: Ofrece contratos on-site." ],
      [ "### Acciona Energía\n\nOfrece **energía limpia**.", "Acciona Energía Ofrece energía limpia." ],
      [ "[Acciona Energía](https://acciona-energia.com): ofrece PPA.", "Acciona Energía: ofrece PPA." ],
      [ "[Acciona Energía][marca]: ofrece PPA.\n\n[marca]: https://acciona-energia.com", "Acciona Energía: ofrece PPA." ],
      [ "<p><strong>H&amp;M</strong> vende ropa.</p>", "H&M vende ropa." ],
      [ "| Empresa | Oferta |\n| --- | --- |\n| Acciona | Energía limpia |", "Acciona Energía limpia" ],
      [ "Acciona\u00a0Energía\n ofrece\tPPA.", "Acciona Energía ofrece PPA." ],
      [ "Acciona Energi\u0301a ofrece “PPA” a 10–20 años.", 'Acciona Energía ofrece "PPA" a 10-20 años.' ],
      [ "**ACCIONA** ofrece energía.", "Acciona ofrece energía." ],
      [ "Acciona\u200b Energía ofrece energía.", "Acciona Energía ofrece energía." ],
      [ "`Code_Name` ofrece software.", "Code_Name ofrece software." ]
    ]
    examples.each do |answer, quote|
      assert Visibility::EvidenceText.new(answer).find(quote), "Rejected visible quote: #{quote.inspect} in #{answer.inspect}"
    end
  end

  test "format normalization cannot invent paraphrase join distant claims or change numbers and negations" do
    document = Visibility::EvidenceText.new("**Acciona** no ofrece contratos a 20 años. Iberdrola ofrece contratos a 10 años.")
    [ "Acciona ofrece contratos a 20 años.", "Acciona no ofrece contratos a 10 años.", "Acciona ofrece contratos a 10 años.", "Acciona vende electricidad barata." ].each do |quote|
      assert_nil document.find(quote), quote
    end
    assert_nil Visibility::EvidenceText.new("Nebulario ofrece software.").find("Nebula", name: true)
    assert_nil Visibility::EvidenceText.new("Acciona").find("Acciona Energía", name: true)
  end

  test "source URLs HTML attributes and hidden content do not establish a mention" do
    source = '[Otra empresa](https://example.com/Acciona) <!-- Acciona --> <span title="Acciona">Otra</span>' \
      '<script>Acciona</script><style>Acciona</style><span hidden>Acciona</span><span style="display: none">Acciona</span>'
    assert_nil Visibility::EvidenceText.new(source).find("Acciona", name: true)
  end

  test "name anchors tolerate accents and Unicode while retaining the observed spelling" do
    document = Visibility::EvidenceText.new("ACCIONA Energía trabaja en España.")
    assert_equal "ACCIONA Energía", document.find("acciona energia", name: true)
    assert_nil document.find("Aciona Energía", name: true), "Typos are resolved semantically, never invented inside a quote"
  end
end

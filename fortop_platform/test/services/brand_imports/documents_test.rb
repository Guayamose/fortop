require "test_helper"

class BrandDocumentsExtractionTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(github_id: 880041, login: "doc-reader", github_token: "fake")
    @import = @user.brand_imports.create!
  end

  test "reads UTF-8 text without executing markup and refuses content that would be truncated" do
    text = "Nébula ayuda a pequeñas empresas. <script>alert('test')</script>"
    assert_equal text, extract("brief.md", text)
    assert_raises(Visibility::Error) { extract("large.txt", "a" * (BrandImports::Documents::MAX_TEXT + 1)) }
    assert_raises(Visibility::Error) { extract("empty.txt", " ") }
  end

  test "reads paragraphs and tables from Word and ordered slides plus speaker notes from PowerPoint" do
    word = office("word/document.xml" => '<w:document xmlns:w="urn:word"><w:body><w:p><w:r><w:t>Nébula ofrece </w:t></w:r><w:r><w:t>facturación.</w:t></w:r></w:p><w:tbl><w:tr><w:tc><w:p><w:r><w:t>Público: pymes de España.</w:t></w:r></w:p></w:tc></w:tr></w:tbl></w:body></w:document>')
    assert_equal "Nébula ofrece facturación.\nPúblico: pymes de España.", extract("dossier.docx", word)
    slides = office("ppt/slides/slide2.xml" => slide("Segundo mercado: Portugal."), "ppt/slides/slide1.xml" => slide("Primer mercado: España."), "ppt/notesSlides/notesSlide1.xml" => slide("Nota: soporte cercano."))
    result = extract("marca.pptx", slides)
    assert_includes result, "Nota: soporte cercano."
    assert_operator result.index("Primer mercado"), :<, result.index("Segundo mercado")
    assert_raises(Visibility::Error) { extract("broken.docx", "not a zip") }
  end

  test "extracts a real digital PDF and rejects damaged PDF files" do
    content = "BT /F1 12 Tf 72 700 Td (Fortop helps small businesses in Spain.) Tj ET"
    objects = [ "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>", "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>", "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>", "<< /Length #{content.bytesize} >>\nstream\n#{content}\nendstream" ]
    pdf = "%PDF-1.4\n"
    offsets = objects.each_with_index.map { |object, index| offset = pdf.bytesize; pdf << "#{index + 1} 0 obj\n#{object}\nendobj\n"; offset }
    xref = pdf.bytesize
    pdf << "xref\n0 6\n0000000000 65535 f \n" + offsets.map { |offset| "%010d 00000 n \n" % offset }.join
    pdf << "trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n#{xref}\n%%EOF\n"
    assert_includes extract("dossier.pdf", pdf), "Fortop helps small businesses in Spain."
    assert_raises(Visibility::Error) { extract("broken.pdf", "%PDF damaged") }
  end

  private

  def extract(name, content)
    document = @import.documents.create!
    document.file.attach(io: StringIO.new(content), filename: name, identify: false)
    BrandImports::Documents.extract(document)
  end

  def office(entries)
    Zip::OutputStream.write_buffer { |zip| entries.each { |name, xml| zip.put_next_entry(name); zip.write(xml) } }.string
  end

  def slide(text)
    "<a:root xmlns:a='urn:drawing'><a:p><a:r><a:t>#{text}</a:t></a:r></a:p></a:root>"
  end
end

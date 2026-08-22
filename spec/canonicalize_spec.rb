# frozen_string_literal: true

RSpec.describe NEU::MODS::Canonicalize do
  describe ".canonical_ws" do
    it "folds NBSP to space, collapses runs, and strips" do
      nbsp = [0xA0].pack("U")
      expect(NEU::MODS.canonical_ws("  a#{nbsp}#{nbsp} b\t c  ")).to eq("a b c")
    end

    it "treats nil as empty" do
      expect(NEU::MODS.canonical_ws(nil)).to eq("")
    end
  end

  describe ".whitespace_equivalent?" do
    it "is true for values differing only by insignificant whitespace" do
      nbsp = [0xA0].pack("U")
      expect(NEU::MODS.whitespace_equivalent?("Hello#{nbsp}World", "Hello World")).to be(true)
      expect(NEU::MODS.whitespace_equivalent?("a  b", " a b ")).to be(true)
    end

    it "is false for a real content change" do
      expect(NEU::MODS.whitespace_equivalent?("Hello", "Goodbye")).to be(false)
    end
  end
end

RSpec.describe NEU::MODS::TextNormalizer do
  # Built from codepoints, so this spec file stays pure ASCII on disk like lib/.
  let(:vt) { [0x000B].pack("U") } # vertical tab -- Word's manual line break
  let(:ff) { [0x000C].pack("U") } # form feed -- Word's page break

  describe ".normalize_paragraphs" do
    it "collapses soft-wrap newlines within a paragraph but keeps paragraph breaks" do
      input = "Line one\n        continues here.\n\nA second paragraph."
      expect(NEU::MODS.normalize_paragraphs(input))
        .to eq("Line one continues here.\n\nA second paragraph.")
    end

    it "collapses 3+ blank lines to a single paragraph break" do
      expect(NEU::MODS.normalize_paragraphs("a\n\n\n\nb")).to eq("a\n\nb")
    end

    it "transliterates smart punctuation to ASCII" do
      # built from codepoints so this spec file itself stays ASCII
      smart = [0x201C, 0x68, 0x69, 0x201D, 0x2026].pack("U*") # “hi”…
      expect(NEU::MODS.normalize_paragraphs(smart)).to eq('"hi"...')
    end

    # Word writes a manual line break as U+000B and a page break as U+000C.
    # Deleting either would weld the words on both sides of it together.
    it "reads a separator control as the soft wrap it stands for" do
      expect(NEU::MODS.normalize_paragraphs("one#{vt}two")).to eq("one two")
      expect(NEU::MODS.normalize_paragraphs("one#{ff}two")).to eq("one two")
    end

    it "reads a run of two separator controls as a paragraph break" do
      expect(NEU::MODS.normalize_paragraphs("one#{vt}#{vt}two")).to eq("one\n\ntwo")
    end

    it "still drops a control that carries no meaning" do
      nul = [0x0000].pack("U")
      c1 = [0x0092].pack("U") # the Windows-1252 mojibake signature
      expect(NEU::MODS.normalize_paragraphs("one#{nul}#{c1}two")).to eq("onetwo")
    end

    it "reduces a CRLF line ending to one newline, not a paragraph break" do
      expect(NEU::MODS.normalize_paragraphs("one\r\ntwo")).to eq("one two")
      expect(NEU::MODS.normalize_paragraphs("one\r\n\r\ntwo")).to eq("one\n\ntwo")
    end
  end

  describe ".normalize" do
    it "turns newlines into spaces for single-line fields" do
      expect(NEU::MODS.normalize("a\nb")).to eq("a b")
    end

    it "turns a separator control into a space" do
      expect(NEU::MODS.normalize("one#{vt}two")).to eq("one two")
      expect(NEU::MODS.normalize("one#{ff}two")).to eq("one two")
    end

    # Solr discards a soft hyphen, so "co<00AD>operation" already matches a
    # search for "cooperation". An ASCII hyphen in its place would index "co"
    # and "operation" as two tokens and lose the word.
    it "drops a soft hyphen rather than making it a visible hyphen" do
      shy = [0x00AD].pack("U")
      expect(NEU::MODS.normalize("co#{shy}operation")).to eq("cooperation")
      expect(NEU::MODS.normalize_paragraphs("co#{shy}operation")).to eq("cooperation")
    end

    it "still folds a dash that a reader can see" do
      en_dash = [0x2013].pack("U")
      expect(NEU::MODS.normalize("1900#{en_dash}1910")).to eq("1900-1910")
    end
  end
end

# Regression guard: the TextNormalizer port must stay pure ASCII on disk (no
# literal control bytes / smart chars). This is exactly the bug we hit building
# it — every char-class regex must be constructed from \uXXXX escapes.
RSpec.describe "source ASCII purity" do
  it "keeps every lib/ file pure ASCII" do
    Dir[File.expand_path("../lib/**/*.rb", __dir__)].each do |path|
      bytes = File.binread(path).bytes
      offenders = bytes.each_with_index.select { |b, _| b > 127 }
      expect(offenders).to be_empty, "#{path} has non-ASCII bytes at #{offenders.map(&:last).first(5)}"
    end
  end
end

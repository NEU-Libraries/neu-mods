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
  end

  describe ".normalize" do
    it "turns newlines into spaces for single-line fields" do
      expect(NEU::MODS.normalize("a\nb")).to eq("a b")
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

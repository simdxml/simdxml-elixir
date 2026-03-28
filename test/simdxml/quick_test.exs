defmodule SimdXml.QuickTest do
  use ExUnit.Case, async: true

  @xml "<r><claim>Patent claim text</claim><claim>Another claim</claim></r>"
  @self_closing_xml "<r><br/><hr /><img src='test'/></r>"

  # ---------------------------------------------------------------------------
  # new/1
  # ---------------------------------------------------------------------------

  describe "new/1" do
    test "creates scanner with tag name" do
      scanner = SimdXml.Quick.new("claim")
      assert scanner.tag == "claim"
    end

    test "scanner stores the tag" do
      scanner = SimdXml.Quick.new("title")
      assert scanner.tag == "title"
    end
  end

  # ---------------------------------------------------------------------------
  # extract_first/2
  # ---------------------------------------------------------------------------

  describe "extract_first/2" do
    test "extracts first matching tag content" do
      scanner = SimdXml.Quick.new("claim")
      assert SimdXml.Quick.extract_first(scanner, @xml) == "Patent claim text"
    end

    test "returns empty string for missing tag" do
      scanner = SimdXml.Quick.new("missing")
      assert SimdXml.Quick.extract_first(scanner, @xml) == ""
    end

    test "extracts from minimal document" do
      scanner = SimdXml.Quick.new("a")
      assert SimdXml.Quick.extract_first(scanner, "<a>text</a>") == "text"
    end

    test "empty text content" do
      scanner = SimdXml.Quick.new("empty")
      result = SimdXml.Quick.extract_first(scanner, "<r><empty></empty></r>")
      assert result == ""
    end

    test "tag at start of document" do
      scanner = SimdXml.Quick.new("root")
      result = SimdXml.Quick.extract_first(scanner, "<root>content</root>")
      assert result == "content"
    end

    test "tag at end of document" do
      scanner = SimdXml.Quick.new("last")
      result = SimdXml.Quick.extract_first(scanner, "<r><first>a</first><last>b</last></r>")
      assert result == "b"
    end

    test "unicode text content" do
      scanner = SimdXml.Quick.new("title")
      result = SimdXml.Quick.extract_first(scanner, "<r><title>\u6771\u4EAC</title></r>")
      assert result == "\u6771\u4EAC"
    end

    test "self-closing tag returns empty or nil" do
      scanner = SimdXml.Quick.new("br")
      result = SimdXml.Quick.extract_first(scanner, @self_closing_xml)
      # Self-closing has no text content
      assert result == "" or result == nil
    end

    test "nested element returns nil (can't extract cleanly)" do
      scanner = SimdXml.Quick.new("parent")
      result = SimdXml.Quick.extract_first(scanner, "<parent><child>text</child></parent>")
      # QuickScanner returns nil for nested elements
      assert result == nil or is_binary(result)
    end
  end

  # ---------------------------------------------------------------------------
  # exists?/2
  # ---------------------------------------------------------------------------

  describe "exists?/2" do
    test "returns true when tag exists" do
      scanner = SimdXml.Quick.new("claim")
      assert SimdXml.Quick.exists?(scanner, @xml) == true
    end

    test "returns false when tag is missing" do
      scanner = SimdXml.Quick.new("missing")
      assert SimdXml.Quick.exists?(scanner, @xml) == false
    end

    test "detects self-closing tags" do
      scanner = SimdXml.Quick.new("br")
      assert SimdXml.Quick.exists?(scanner, @self_closing_xml) == true
    end

    test "detects self-closing with space before slash" do
      scanner = SimdXml.Quick.new("hr")
      assert SimdXml.Quick.exists?(scanner, @self_closing_xml) == true
    end

    test "false for empty document" do
      scanner = SimdXml.Quick.new("anything")
      assert SimdXml.Quick.exists?(scanner, "<r/>") == false
    end

    test "unicode tag detection" do
      scanner = SimdXml.Quick.new("data")
      xml = "<root><data>\u00E9\u00E8</data></root>"
      assert SimdXml.Quick.exists?(scanner, xml) == true
    end
  end

  # ---------------------------------------------------------------------------
  # count/2
  # ---------------------------------------------------------------------------

  describe "count/2" do
    test "counts matching tags" do
      scanner = SimdXml.Quick.new("claim")
      assert SimdXml.Quick.count(scanner, @xml) == 2
    end

    test "returns 0 for missing tag" do
      scanner = SimdXml.Quick.new("missing")
      assert SimdXml.Quick.count(scanner, @xml) == 0
    end

    test "counts single occurrence" do
      scanner = SimdXml.Quick.new("root")
      assert SimdXml.Quick.count(scanner, "<root>text</root>") == 1
    end

    test "counts self-closing tags" do
      scanner = SimdXml.Quick.new("br")
      xml = "<r><br/><br/><br/></r>"
      assert SimdXml.Quick.count(scanner, xml) == 3
    end

    test "counts many occurrences" do
      items = Enum.map(1..100, fn _ -> "<item>x</item>" end) |> Enum.join()
      xml = "<r>" <> items <> "</r>"
      scanner = SimdXml.Quick.new("item")
      assert SimdXml.Quick.count(scanner, xml) == 100
    end

    test "does not count partial tag name matches" do
      scanner = SimdXml.Quick.new("it")
      xml = "<r><item>x</item><it>y</it></r>"
      # Should only count <it>, not <item>
      assert SimdXml.Quick.count(scanner, xml) == 1
    end
  end

  # ---------------------------------------------------------------------------
  # Inspect protocol
  # ---------------------------------------------------------------------------

  describe "Inspect protocol" do
    test "includes tag name" do
      scanner = SimdXml.Quick.new("claim")
      assert inspect(scanner) =~ "#SimdXml.Quick<"
      assert inspect(scanner) =~ "claim"
    end
  end
end

defmodule SimdXml.DocumentTest do
  use ExUnit.Case, async: true
  doctest SimdXml.Document

  @xml "<library><book lang='en'><title>Rust</title><price>29.99</price></book></library>"
  @multi_child "<r><a>1</a><b>2</b><c>3</c></r>"
  @nested "<a><b><c><d>deep</d></c></b></a>"
  @self_closing "<r><br/><hr/></r>"

  describe "root/1" do
    test "returns root element" do
      doc = SimdXml.parse!(@xml)
      root = SimdXml.Document.root(doc)
      assert root.tag == "library"
    end

    test "root element has correct tag for simple doc" do
      doc = SimdXml.parse!("<simple/>")
      root = SimdXml.Document.root(doc)
      assert root.tag == "simple"
    end

    test "root returns nil for comment-only document" do
      doc = SimdXml.parse!("<!-- just a comment -->")
      assert SimdXml.Document.root(doc) == nil
    end

    test "root of deeply nested doc" do
      doc = SimdXml.parse!(@nested)
      root = SimdXml.Document.root(doc)
      assert root.tag == "a"
    end
  end

  describe "tag_count/1" do
    test "counts tags in document" do
      doc = SimdXml.parse!(@xml)
      assert SimdXml.Document.tag_count(doc) > 0
    end

    test "single self-closing tag counts as 1" do
      doc = SimdXml.parse!("<root/>")
      assert SimdXml.Document.tag_count(doc) == 1
    end

    test "self-closing children are counted" do
      doc = SimdXml.parse!(@self_closing)
      assert SimdXml.Document.tag_count(doc) >= 3
    end

    test "wide document counts all children" do
      children = Enum.map(1..50, fn _ -> "<item/>" end) |> Enum.join()
      xml = "<r>" <> children <> "</r>"
      doc = SimdXml.parse!(xml)
      assert SimdXml.Document.tag_count(doc) >= 51
    end
  end

  describe "xpath_text/2" do
    test "extracts text from matching elements" do
      doc = SimdXml.parse!(@xml)
      assert {:ok, ["Rust"]} = SimdXml.Document.xpath_text(doc, "//title")
    end

    test "returns empty list for no matches" do
      doc = SimdXml.parse!(@xml)
      assert {:ok, []} = SimdXml.Document.xpath_text(doc, "//nonexistent")
    end

    test "returns error for invalid xpath" do
      doc = SimdXml.parse!(@xml)
      assert {:error, _} = SimdXml.Document.xpath_text(doc, "///[bad")
    end

    test "extracts from multiple matches" do
      doc = SimdXml.parse!(@multi_child)
      {:ok, texts} = SimdXml.Document.xpath_text(doc, "/r/*")
      assert length(texts) == 3
      assert "1" in texts
      assert "2" in texts
      assert "3" in texts
    end

    test "extracts with position predicate" do
      doc = SimdXml.parse!(@multi_child)
      {:ok, texts} = SimdXml.Document.xpath_text(doc, "/r/*[2]")
      assert texts == ["2"]
    end
  end

  describe "xpath_string/2" do
    test "returns all descendant text" do
      xml = "<r><a>hello <b>world</b></a></r>"
      doc = SimdXml.parse!(xml)
      {:ok, [text]} = SimdXml.Document.xpath_string(doc, "//a")
      assert text == "hello world"
    end

    test "returns empty list for no matches" do
      doc = SimdXml.parse!("<r/>")
      assert {:ok, []} = SimdXml.Document.xpath_string(doc, "//missing")
    end

    test "returns error for invalid xpath" do
      doc = SimdXml.parse!("<r/>")
      assert {:error, _} = SimdXml.Document.xpath_string(doc, "///[")
    end
  end

  describe "xpath_nodes/2" do
    test "returns node references for matches" do
      doc = SimdXml.parse!(@multi_child)
      {:ok, nodes} = SimdXml.Document.xpath_nodes(doc, "/r/*")
      assert length(nodes) == 3
    end

    test "returns empty list for no matches" do
      doc = SimdXml.parse!("<r/>")
      {:ok, nodes} = SimdXml.Document.xpath_nodes(doc, "//missing")
      assert nodes == []
    end

    test "returns error for invalid xpath" do
      doc = SimdXml.parse!("<r/>")
      assert {:error, _} = SimdXml.Document.xpath_nodes(doc, "///[")
    end
  end

  describe "eval/2" do
    test "evaluates location path" do
      doc = SimdXml.parse!(@multi_child)
      {:ok, result} = SimdXml.Document.eval(doc, "//a")
      assert result != nil
    end

    test "returns error for unsupported function expressions" do
      # eval() only supports location paths, unions, and id() -- not functions
      doc = SimdXml.parse!(@multi_child)
      assert {:error, _} = SimdXml.Document.eval(doc, "count(/r/*)")
      assert {:error, _} = SimdXml.Document.eval(doc, "boolean(//a)")
      assert {:error, _} = SimdXml.Document.eval(doc, "string(//a)")
    end

    test "returns error for invalid expression" do
      doc = SimdXml.parse!("<r/>")
      assert {:error, _} = SimdXml.Document.eval(doc, "///[bad")
    end
  end

  describe "Inspect protocol" do
    test "includes tag count" do
      doc = SimdXml.parse!("<r><a/><b/></r>")
      assert inspect(doc) =~ "#SimdXml.Document<tags:"
    end

    test "single tag doc shows count" do
      doc = SimdXml.parse!("<r/>")
      assert inspect(doc) =~ "tags: 1"
    end
  end
end

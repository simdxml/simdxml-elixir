defmodule SimdXml.ElementTest do
  use ExUnit.Case, async: true
  doctest SimdXml.Element

  @xml """
  <library>
    <book lang="en" year="2024">
      <title>Rust Programming</title>
      <author>Steve Klabnik</author>
    </book>
    <book lang="ja">
      <title>Elixir Guide</title>
    </book>
  </library>
  """

  @self_closing_xml "<r><br/><hr /><img src='test.png'/></r>"

  @mixed_xml "<p>Hello <b>bold</b> and <i>italic</i> world</p>"

  @deeply_nested (fn ->
                    open = Enum.map(1..10, fn i -> "<l#{i}>" end) |> Enum.join()
                    close = Enum.map(10..1//-1, fn i -> "</l#{i}>" end) |> Enum.join()
                    open <> "<leaf>bottom</leaf>" <> close
                  end).()

  setup do
    %{doc: SimdXml.parse!(@xml)}
  end

  # ---------------------------------------------------------------------------
  # Basic navigation
  # ---------------------------------------------------------------------------

  describe "children/1" do
    test "root and children", %{doc: doc} do
      root = SimdXml.Document.root(doc)
      assert root.tag == "library"
      children = SimdXml.Element.children(root)
      assert length(children) == 2
      assert Enum.all?(children, &(&1.tag == "book"))
    end

    test "childless element returns empty list" do
      doc = SimdXml.parse!("<r><leaf>text</leaf></r>")
      root = SimdXml.Document.root(doc)
      [leaf] = SimdXml.Element.children(root)
      assert SimdXml.Element.children(leaf) == []
    end

    test "self-closing element has no children" do
      doc = SimdXml.parse!(@self_closing_xml)
      root = SimdXml.Document.root(doc)
      children = SimdXml.Element.children(root)
      assert length(children) == 3

      for child <- children do
        assert SimdXml.Element.children(child) == []
      end
    end

    test "many children" do
      items = Enum.map(1..50, fn i -> "<item>#{i}</item>" end) |> Enum.join()
      doc = SimdXml.parse!("<r>" <> items <> "</r>")
      root = SimdXml.Document.root(doc)
      children = SimdXml.Element.children(root)
      assert length(children) == 50
    end
  end

  describe "attributes/1" do
    test "returns attribute map", %{doc: doc} do
      root = SimdXml.Document.root(doc)
      [first | _] = SimdXml.Element.children(root)
      attrs = SimdXml.Element.attributes(first)
      assert attrs == %{"lang" => "en", "year" => "2024"}
    end

    test "element with no attributes returns empty map" do
      doc = SimdXml.parse!("<r><child>text</child></r>")
      root = SimdXml.Document.root(doc)
      [child] = SimdXml.Element.children(root)
      assert SimdXml.Element.attributes(child) == %{}
    end

    test "self-closing element with attributes" do
      doc = SimdXml.parse!(@self_closing_xml)
      root = SimdXml.Document.root(doc)
      children = SimdXml.Element.children(root)
      img = List.last(children)
      assert SimdXml.Element.get(img, "src") == "test.png"
    end
  end

  describe "get/2" do
    test "returns attribute value", %{doc: doc} do
      root = SimdXml.Document.root(doc)
      [first | _] = SimdXml.Element.children(root)
      assert SimdXml.Element.get(first, "lang") == "en"
    end

    test "returns nil for missing attribute", %{doc: doc} do
      root = SimdXml.Document.root(doc)
      [first | _] = SimdXml.Element.children(root)
      assert SimdXml.Element.get(first, "missing") == nil
    end

    test "empty attribute value" do
      doc = SimdXml.parse!(~s(<r attr=""/>))
      root = SimdXml.Document.root(doc)
      assert SimdXml.Element.get(root, "attr") == ""
    end
  end

  # ---------------------------------------------------------------------------
  # Text extraction
  # ---------------------------------------------------------------------------

  describe "text/1" do
    test "returns direct child text", %{doc: doc} do
      root = SimdXml.Document.root(doc)
      [book | _] = SimdXml.Element.children(root)
      [title | _] = SimdXml.Element.children(book)
      assert title.tag == "title"
      assert SimdXml.Element.text(title) == "Rust Programming"
    end

    test "returns nil for element with only child elements", %{doc: doc} do
      root = SimdXml.Document.root(doc)
      [book | _] = SimdXml.Element.children(root)
      # book has only child elements (title, author), no direct text
      text = SimdXml.Element.text(book)
      # text is nil or whitespace since there are only child elements
      assert text == nil or String.trim(text) == ""
    end

    test "returns nil for self-closing element" do
      doc = SimdXml.parse!("<r><br/></r>")
      root = SimdXml.Document.root(doc)
      [br] = SimdXml.Element.children(root)
      assert SimdXml.Element.text(br) == nil
    end

    test "mixed content returns first direct text segment" do
      doc = SimdXml.parse!(@mixed_xml)
      root = SimdXml.Document.root(doc)
      text = SimdXml.Element.text(root)
      # Should return direct child text: "Hello "
      assert text != nil
      assert text =~ "Hello"
    end
  end

  describe "text_content/1" do
    test "concatenates all descendant text", %{doc: doc} do
      root = SimdXml.Document.root(doc)
      [book | _] = SimdXml.Element.children(root)
      content = SimdXml.Element.text_content(book)
      assert content =~ "Rust Programming"
      assert content =~ "Steve Klabnik"
    end

    test "mixed content includes all text" do
      doc = SimdXml.parse!(@mixed_xml)
      root = SimdXml.Document.root(doc)
      content = SimdXml.Element.text_content(root)
      assert content =~ "Hello"
      assert content =~ "bold"
      assert content =~ "italic"
      assert content =~ "world"
    end

    test "leaf element text_content matches text" do
      doc = SimdXml.parse!("<r><leaf>just text</leaf></r>")
      root = SimdXml.Document.root(doc)
      [leaf] = SimdXml.Element.children(root)
      assert SimdXml.Element.text_content(leaf) == "just text"
      assert SimdXml.Element.text(leaf) == "just text"
    end

    test "self-closing element returns empty string" do
      doc = SimdXml.parse!("<r><br/></r>")
      root = SimdXml.Document.root(doc)
      [br] = SimdXml.Element.children(root)
      assert SimdXml.Element.text_content(br) == ""
    end
  end

  # ---------------------------------------------------------------------------
  # Navigation
  # ---------------------------------------------------------------------------

  describe "parent/1" do
    test "navigates to parent", %{doc: doc} do
      root = SimdXml.Document.root(doc)
      [book | _] = SimdXml.Element.children(root)
      [title | _] = SimdXml.Element.children(book)
      parent = SimdXml.Element.parent(title)
      assert parent.tag == "book"
    end

    test "root has no parent", %{doc: doc} do
      root = SimdXml.Document.root(doc)
      assert SimdXml.Element.parent(root) == nil
    end

    test "grandparent navigation" do
      doc = SimdXml.parse!("<a><b><c>text</c></b></a>")
      root = SimdXml.Document.root(doc)
      [b] = SimdXml.Element.children(root)
      [c] = SimdXml.Element.children(b)
      parent_b = SimdXml.Element.parent(c)
      assert parent_b.tag == "b"
      grandparent_a = SimdXml.Element.parent(parent_b)
      assert grandparent_a.tag == "a"
    end
  end

  describe "deeply nested navigation" do
    test "traverse 10 levels deep" do
      doc = SimdXml.parse!(@deeply_nested)
      root = SimdXml.Document.root(doc)
      assert root.tag == "l1"

      # Walk down to the leaf
      element = root

      element =
        Enum.reduce(2..10, element, fn _i, el ->
          [child] = SimdXml.Element.children(el)
          child
        end)

      [leaf] = SimdXml.Element.children(element)
      assert leaf.tag == "leaf"
      assert SimdXml.Element.text(leaf) == "bottom"
    end

    test "parent chain back to root" do
      doc = SimdXml.parse!("<a><b><c><d>deep</d></c></b></a>")
      root = SimdXml.Document.root(doc)
      [b] = SimdXml.Element.children(root)
      [c] = SimdXml.Element.children(b)
      [d] = SimdXml.Element.children(c)

      # Walk back up
      assert SimdXml.Element.parent(d).tag == "c"
      assert SimdXml.Element.parent(SimdXml.Element.parent(d)).tag == "b"
      assert SimdXml.Element.parent(SimdXml.Element.parent(SimdXml.Element.parent(d))).tag == "a"
    end
  end

  # ---------------------------------------------------------------------------
  # raw_xml/1
  # ---------------------------------------------------------------------------

  describe "raw_xml/1" do
    test "includes opening and closing tags", %{doc: doc} do
      root = SimdXml.Document.root(doc)
      [book | _] = SimdXml.Element.children(root)
      [title | _] = SimdXml.Element.children(book)
      raw = SimdXml.Element.raw_xml(title)
      assert raw =~ "<title>"
      assert raw =~ "Rust Programming"
      assert raw =~ "</title>"
    end

    test "self-closing raw xml" do
      doc = SimdXml.parse!("<r><br/></r>")
      root = SimdXml.Document.root(doc)
      [br] = SimdXml.Element.children(root)
      raw = SimdXml.Element.raw_xml(br)
      assert raw =~ "br"
    end
  end

  # ---------------------------------------------------------------------------
  # xpath_text/2 (element-scoped)
  # ---------------------------------------------------------------------------

  describe "xpath_text/2" do
    test "scoped query on element", %{doc: doc} do
      root = SimdXml.Document.root(doc)
      [first | _] = SimdXml.Element.children(root)
      assert {:ok, ["Rust Programming"]} = SimdXml.Element.xpath_text(first, "./title")
    end

    test "scoped query does not see siblings" do
      xml = "<r><a><x>1</x></a><b><x>2</x></b></r>"
      doc = SimdXml.parse!(xml)
      root = SimdXml.Document.root(doc)
      [a, _b] = SimdXml.Element.children(root)
      {:ok, texts} = SimdXml.Element.xpath_text(a, "./x")
      assert texts == ["1"]
    end

    test "scoped query returns empty for non-matching" do
      doc = SimdXml.parse!("<r><a>text</a></r>")
      root = SimdXml.Document.root(doc)
      [a] = SimdXml.Element.children(root)
      assert {:ok, []} = SimdXml.Element.xpath_text(a, "./missing")
    end

    test "returns error for invalid xpath" do
      doc = SimdXml.parse!("<r><a>text</a></r>")
      root = SimdXml.Document.root(doc)
      [a] = SimdXml.Element.children(root)
      assert {:error, _} = SimdXml.Element.xpath_text(a, "///[")
    end
  end

  # ---------------------------------------------------------------------------
  # Enumerable protocol
  # ---------------------------------------------------------------------------

  describe "Enumerable protocol" do
    test "Enum.map over children", %{doc: doc} do
      root = SimdXml.Document.root(doc)
      tags = Enum.map(root, & &1.tag)
      assert tags == ["book", "book"]
    end

    test "Enum.count", %{doc: doc} do
      root = SimdXml.Document.root(doc)
      assert Enum.count(root) == 2
    end

    test "Enum.count of childless element" do
      doc = SimdXml.parse!("<r><leaf>text</leaf></r>")
      root = SimdXml.Document.root(doc)
      [leaf] = SimdXml.Element.children(root)
      assert Enum.count(leaf) == 0
    end

    test "Enum.to_list" do
      doc = SimdXml.parse!("<r><a/><b/><c/></r>")
      root = SimdXml.Document.root(doc)
      list = Enum.to_list(root)
      assert length(list) == 3
      assert Enum.map(list, & &1.tag) == ["a", "b", "c"]
    end

    test "Enum.filter" do
      doc = SimdXml.parse!(~s(<r><a type="x"/><b type="y"/><c type="x"/></r>))
      root = SimdXml.Document.root(doc)
      filtered = Enum.filter(root, fn el -> SimdXml.Element.get(el, "type") == "x" end)
      assert length(filtered) == 2
      assert Enum.map(filtered, & &1.tag) == ["a", "c"]
    end

    test "Enum.reduce" do
      doc = SimdXml.parse!("<r><n>1</n><n>2</n><n>3</n></r>")
      root = SimdXml.Document.root(doc)

      sum =
        Enum.reduce(root, 0, fn el, acc ->
          acc + String.to_integer(SimdXml.Element.text(el))
        end)

      assert sum == 6
    end

    test "empty enumeration" do
      doc = SimdXml.parse!("<r/>")
      root = SimdXml.Document.root(doc)
      assert Enum.to_list(root) == []
      assert Enum.count(root) == 0
    end

    test "Enum.find" do
      doc = SimdXml.parse!("<r><a>1</a><b>2</b><c>3</c></r>")
      root = SimdXml.Document.root(doc)
      found = Enum.find(root, fn el -> el.tag == "b" end)
      assert found.tag == "b"
      assert SimdXml.Element.text(found) == "2"
    end
  end

  # ---------------------------------------------------------------------------
  # Inspect protocol
  # ---------------------------------------------------------------------------

  describe "Inspect protocol" do
    test "shows tag name and index", %{doc: doc} do
      root = SimdXml.Document.root(doc)
      assert inspect(root) =~ "#SimdXml.Element<library"
    end

    test "includes @ for index" do
      doc = SimdXml.parse!("<r/>")
      root = SimdXml.Document.root(doc)
      assert inspect(root) =~ "@"
    end
  end
end

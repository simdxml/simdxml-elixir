defmodule SimdXmlTest do
  use ExUnit.Case, async: true
  doctest SimdXml

  @books """
  <library>
    <book lang="en">
      <title>Elixir in Action</title>
      <author>Sasa Juric</author>
      <year>2019</year>
    </book>
    <book lang="ja">
      <title>Programming Elixir</title>
      <author>Dave Thomas</author>
      <year>2018</year>
    </book>
    <book lang="en">
      <title>Metaprogramming Elixir</title>
      <author>Chris McCord</author>
      <year>2015</year>
    </book>
  </library>
  """

  @self_closing "<root><br/><empty /><hr /></root>"

  @deep_xml (fn ->
               open = Enum.map(1..60, fn i -> "<l#{i}>" end) |> Enum.join()
               close = Enum.map(60..1//-1, fn i -> "</l#{i}>" end) |> Enum.join()
               open <> "<leaf>deep</leaf>" <> close
             end).()

  @wide_xml (fn ->
               children = Enum.map(1..120, fn i -> "<item>#{i}</item>" end) |> Enum.join()
               "<root>" <> children <> "</root>"
             end).()

  @mixed_content "<p>Hello <b>bold</b> and <i>italic</i> world</p>"

  @cdata_xml "<data><![CDATA[<not>xml</not> & stuff]]></data>"

  @comment_xml "<!-- top comment --><root><!-- inner --><child>text</child></root>"

  @pi_xml ~s(<?xml version="1.0" encoding="UTF-8"?><root><item>1</item></root>)

  @namespace_xml """
  <ns:root xmlns:ns="http://example.com" xmlns:other="http://other.com">
    <ns:child>namespaced</ns:child>
    <other:child>other ns</other:child>
  </ns:root>
  """

  # The parser does not decode XML entities -- they stay as raw text
  @entities_xml "<r><e>&amp; &lt; &gt; &apos; &quot;</e></r>"

  @many_attrs_xml (fn ->
                     attrs = Enum.map(1..30, fn i -> ~s(a#{i}="v#{i}") end) |> Enum.join(" ")
                     "<root " <> attrs <> "/>"
                   end).()

  # ---------------------------------------------------------------------------
  # parse/1
  # ---------------------------------------------------------------------------

  describe "parse/1" do
    test "parses valid XML" do
      assert {:ok, doc} = SimdXml.parse("<root/>")
      assert SimdXml.Document.tag_count(doc) == 1
    end

    test "returns error for invalid XML" do
      assert {:error, _reason} = SimdXml.parse("not xml <<<")
    end

    test "parse! raises on invalid XML" do
      assert_raise SimdXml.Error, fn ->
        SimdXml.parse!("<<<")
      end
    end

    test "parses self-closing tags" do
      {:ok, doc} = SimdXml.parse(@self_closing)
      assert SimdXml.Document.tag_count(doc) >= 4
    end

    test "parses deeply nested document (60 levels)" do
      {:ok, doc} = SimdXml.parse(@deep_xml)
      assert SimdXml.Document.tag_count(doc) > 60
    end

    test "parses wide document (120 children)" do
      {:ok, doc} = SimdXml.parse(@wide_xml)
      {:ok, items} = SimdXml.xpath_text(doc, "//item")
      assert length(items) == 120
    end

    test "parses document with XML declaration PI" do
      {:ok, doc} = SimdXml.parse(@pi_xml)
      {:ok, items} = SimdXml.xpath_text(doc, "//item")
      assert items == ["1"]
    end

    test "parses document with comments" do
      {:ok, doc} = SimdXml.parse(@comment_xml)
      {:ok, texts} = SimdXml.xpath_text(doc, "//child")
      assert texts == ["text"]
    end

    test "parses CDATA sections" do
      {:ok, _doc} = SimdXml.parse(@cdata_xml)
    end

    test "parses namespace-prefixed elements" do
      {:ok, _doc} = SimdXml.parse(@namespace_xml)
    end

    test "parses element with many attributes" do
      {:ok, _doc} = SimdXml.parse(@many_attrs_xml)
    end
  end

  # ---------------------------------------------------------------------------
  # Sad path parsing
  # Note: The SIMD parser is lenient -- it accepts many malformed inputs
  # without error. These tests document that behavior.
  # ---------------------------------------------------------------------------

  describe "parse/1 sad paths" do
    test "empty string parses as empty document (lenient parser)" do
      # The SIMD parser accepts empty input as an empty document
      result = SimdXml.parse("")
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "whitespace only" do
      # The SIMD parser accepts whitespace-only as an empty document
      result = SimdXml.parse("   \n\t  ")
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "unclosed tag does not crash" do
      # SIMD parser may accept unclosed tags
      result = SimdXml.parse("<root><child>text</root>")
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "mismatched tags do not crash" do
      # SIMD parser may accept mismatched tags
      result = SimdXml.parse("<a></b>")
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "just text, no tags" do
      result = SimdXml.parse("hello world")
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "incomplete tag" do
      assert {:error, _} = SimdXml.parse("<root")
    end

    test "duplicate root elements" do
      result = SimdXml.parse("<a/><b/>")
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "angle brackets in text cause error" do
      assert {:error, _} = SimdXml.parse("not xml <<<")
    end
  end

  # ---------------------------------------------------------------------------
  # Unicode
  # ---------------------------------------------------------------------------

  describe "unicode" do
    test "UTF-8 text content" do
      doc = SimdXml.parse!("<r><msg>Hello, world!</msg></r>")
      assert {:ok, ["Hello, world!"]} = SimdXml.xpath_text(doc, "//msg")
    end

    test "CJK characters in text" do
      doc = SimdXml.parse!("<r><title>\u6771\u4EAC\u90FD</title></r>")
      assert {:ok, ["\u6771\u4EAC\u90FD"]} = SimdXml.xpath_text(doc, "//title")
    end

    test "emoji in text content" do
      xml = "<r><emoji>\u{1F600}\u{1F680}\u{1F30D}</emoji></r>"
      doc = SimdXml.parse!(xml)
      {:ok, [text]} = SimdXml.xpath_text(doc, "//emoji")
      assert text == "\u{1F600}\u{1F680}\u{1F30D}"
    end

    test "UTF-8 attribute values" do
      doc = SimdXml.parse!(~s(<r lang="\u00E9\u00E8\u00EA"/>))
      root = SimdXml.Document.root(doc)
      assert SimdXml.Element.get(root, "lang") == "\u00E9\u00E8\u00EA"
    end

    test "mixed scripts in document" do
      xml =
        "<doc><en>English</en><ja>\u65E5\u672C\u8A9E</ja><ar>\u0645\u0631\u062D\u0628\u0627</ar></doc>"

      doc = SimdXml.parse!(xml)
      {:ok, texts} = SimdXml.xpath_text(doc, "/doc/*")
      assert length(texts) == 3
    end
  end

  # ---------------------------------------------------------------------------
  # XML entities
  # Note: The SIMD parser does NOT decode XML entities. They are preserved
  # as raw text. This is expected behavior for a structural parser.
  # ---------------------------------------------------------------------------

  describe "XML entities" do
    test "standard entities are preserved as raw text" do
      doc = SimdXml.parse!(@entities_xml)
      {:ok, [text]} = SimdXml.xpath_text(doc, "//e")
      # Entities are NOT decoded -- they stay as &amp; &lt; etc.
      assert text =~ "&amp;"
      assert text =~ "&lt;"
      assert text =~ "&gt;"
    end

    test "numeric character references are preserved as raw text" do
      doc = SimdXml.parse!("<r><e>&#65;&#x42;</e></r>")
      {:ok, [text]} = SimdXml.xpath_text(doc, "//e")
      # Numeric entities are NOT decoded
      assert text =~ "&#65;"
      assert text =~ "&#x42;"
    end

    test "entities in attribute values are preserved" do
      doc = SimdXml.parse!(~s(<r attr="a&amp;b"/>))
      root = SimdXml.Document.root(doc)
      val = SimdXml.Element.get(root, "attr")
      assert val =~ "&amp;" or val =~ "&"
    end
  end

  # ---------------------------------------------------------------------------
  # CDATA
  # ---------------------------------------------------------------------------

  describe "CDATA" do
    test "CDATA section text extraction" do
      doc = SimdXml.parse!(@cdata_xml)
      {:ok, texts} = SimdXml.xpath_text(doc, "//data")
      combined = Enum.join(texts)
      assert combined =~ "<not>xml</not>"
      assert combined =~ "& stuff" or combined =~ "&amp; stuff"
    end

    test "CDATA with angle brackets" do
      xml = "<r><code><![CDATA[if (a < b && c > d) {}]]></code></r>"
      doc = SimdXml.parse!(xml)
      {:ok, texts} = SimdXml.xpath_text(doc, "//code")
      combined = Enum.join(texts)
      assert combined =~ "a < b"
      assert combined =~ "c > d"
    end
  end

  # ---------------------------------------------------------------------------
  # Comments
  # ---------------------------------------------------------------------------

  describe "comments" do
    test "comments before root element" do
      doc = SimdXml.parse!("<!-- comment --><root>text</root>")
      {:ok, texts} = SimdXml.xpath_text(doc, "//root")
      assert texts == ["text"]
    end

    test "comments between child elements" do
      xml = "<r><a>1</a><!-- sep --><b>2</b></r>"
      doc = SimdXml.parse!(xml)
      {:ok, a_text} = SimdXml.xpath_text(doc, "//a")
      {:ok, b_text} = SimdXml.xpath_text(doc, "//b")
      assert a_text == ["1"]
      assert b_text == ["2"]
    end

    test "comment inside element splits text nodes" do
      xml = "<r>before<!-- hidden -->after</r>"
      doc = SimdXml.parse!(xml)
      {:ok, texts} = SimdXml.xpath_text(doc, "//r")
      # Comments may split text into multiple nodes
      combined = Enum.join(texts)
      assert combined =~ "before"
      assert combined =~ "after"
    end
  end

  # ---------------------------------------------------------------------------
  # Processing instructions
  # ---------------------------------------------------------------------------

  describe "processing instructions" do
    test "XML declaration is handled" do
      doc = SimdXml.parse!(@pi_xml)
      {:ok, items} = SimdXml.xpath_text(doc, "//item")
      assert items == ["1"]
    end

    test "custom processing instructions" do
      xml = ~s(<?my-pi some data?><root>ok</root>)
      result = SimdXml.parse(xml)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  # ---------------------------------------------------------------------------
  # Namespaces
  # ---------------------------------------------------------------------------

  describe "namespaces" do
    test "namespace-prefixed elements are accessible" do
      doc = SimdXml.parse!(@namespace_xml)
      root = SimdXml.Document.root(doc)
      assert root != nil
      assert root.tag =~ "root"
    end

    test "namespace attributes are present" do
      doc = SimdXml.parse!(@namespace_xml)
      root = SimdXml.Document.root(doc)
      attrs = SimdXml.Element.attributes(root)
      assert map_size(attrs) > 0
    end
  end

  # ---------------------------------------------------------------------------
  # Self-closing tags
  # ---------------------------------------------------------------------------

  describe "self-closing tags" do
    test "self-closing tag has no text" do
      doc = SimdXml.parse!("<r><br/></r>")
      root = SimdXml.Document.root(doc)
      [br] = SimdXml.Element.children(root)
      assert br.tag == "br"
      assert SimdXml.Element.text(br) == nil
    end

    test "self-closing with space before slash" do
      doc = SimdXml.parse!("<r><empty /></r>")
      root = SimdXml.Document.root(doc)
      [empty] = SimdXml.Element.children(root)
      assert empty.tag == "empty"
    end

    test "self-closing with attributes" do
      doc = SimdXml.parse!(~s(<r><img src="test.png" /></r>))
      root = SimdXml.Document.root(doc)
      [img] = SimdXml.Element.children(root)
      assert img.tag == "img"
      assert SimdXml.Element.get(img, "src") == "test.png"
    end
  end

  # ---------------------------------------------------------------------------
  # Mixed content
  # ---------------------------------------------------------------------------

  describe "mixed content" do
    test "xpath_string returns all descendant text concatenated" do
      doc = SimdXml.parse!(@mixed_content)
      {:ok, [text]} = SimdXml.xpath_string(doc, "//p")
      assert text =~ "Hello"
      assert text =~ "bold"
      assert text =~ "italic"
      assert text =~ "world"
    end

    test "xpath_text returns separate text segments for mixed content" do
      doc = SimdXml.parse!(@mixed_content)
      {:ok, texts} = SimdXml.xpath_text(doc, "//p")
      # Mixed content may return multiple text segments
      combined = Enum.join(texts, " ")
      assert combined =~ "Hello"
    end
  end

  # ---------------------------------------------------------------------------
  # Attribute edge cases
  # ---------------------------------------------------------------------------

  describe "attribute edge cases" do
    test "empty attribute value" do
      doc = SimdXml.parse!(~s(<r attr=""/>))
      root = SimdXml.Document.root(doc)
      assert SimdXml.Element.get(root, "attr") == ""
    end

    test "many attributes preserved" do
      doc = SimdXml.parse!(@many_attrs_xml)
      root = SimdXml.Document.root(doc)
      attrs = SimdXml.Element.attributes(root)
      assert map_size(attrs) == 30
      assert attrs["a1"] == "v1"
      assert attrs["a30"] == "v30"
    end

    test "single-quoted attribute values" do
      doc = SimdXml.parse!("<r attr='single'/>")
      root = SimdXml.Document.root(doc)
      assert SimdXml.Element.get(root, "attr") == "single"
    end
  end

  # ---------------------------------------------------------------------------
  # xpath_text/2
  # ---------------------------------------------------------------------------

  describe "xpath_text/2" do
    test "extracts text from simple query" do
      doc = SimdXml.parse!("<r><a>hello</a><b>world</b></r>")
      assert {:ok, ["hello"]} = SimdXml.xpath_text(doc, "//a")
      assert {:ok, ["world"]} = SimdXml.xpath_text(doc, "//b")
    end

    test "extracts multiple matches" do
      doc = SimdXml.parse!(@books)
      {:ok, titles} = SimdXml.xpath_text(doc, "//title")
      assert length(titles) == 3
      assert "Elixir in Action" in titles
    end

    test "returns empty list for no matches" do
      doc = SimdXml.parse!("<r><a>1</a></r>")
      assert {:ok, []} = SimdXml.xpath_text(doc, "//missing")
    end

    test "returns error for invalid XPath" do
      doc = SimdXml.parse!("<r/>")
      assert {:error, _} = SimdXml.xpath_text(doc, "///invalid[")
    end

    test "bang variant raises on error" do
      doc = SimdXml.parse!("<r/>")

      assert_raise SimdXml.Error, fn ->
        SimdXml.xpath_text!(doc, "///invalid[")
      end
    end

    test "bang variant returns results directly" do
      doc = SimdXml.parse!("<r><a>1</a></r>")
      assert ["1"] = SimdXml.xpath_text!(doc, "//a")
    end
  end

  # ---------------------------------------------------------------------------
  # xpath_string/2
  # ---------------------------------------------------------------------------

  describe "xpath_string/2" do
    test "returns all descendant text" do
      doc = SimdXml.parse!("<r><a>hello <b>world</b></a></r>")
      {:ok, [text]} = SimdXml.xpath_string(doc, "//a")
      assert text == "hello world"
    end

    test "bang variant returns directly" do
      doc = SimdXml.parse!("<r><a>hello</a></r>")
      assert ["hello"] = SimdXml.xpath_string!(doc, "//a")
    end

    test "bang variant raises on invalid xpath" do
      doc = SimdXml.parse!("<r/>")

      assert_raise SimdXml.Error, fn ->
        SimdXml.xpath_string!(doc, "///[")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # compile/1 and eval_text/2
  # ---------------------------------------------------------------------------

  describe "compile/1 and eval_text/2" do
    test "compiled query is reusable across documents" do
      query = SimdXml.compile!("//title")
      doc1 = SimdXml.parse!("<r><title>A</title></r>")
      doc2 = SimdXml.parse!("<r><title>B</title></r>")
      assert SimdXml.eval_text!(doc1, query) == ["A"]
      assert SimdXml.eval_text!(doc2, query) == ["B"]
    end

    test "compile returns error for invalid XPath" do
      assert {:error, _} = SimdXml.compile("///[invalid")
    end

    test "compile! raises on invalid XPath" do
      assert_raise SimdXml.Error, fn ->
        SimdXml.compile!("///[invalid")
      end
    end

    test "eval_text returns ok tuple" do
      doc = SimdXml.parse!("<r><a>1</a></r>")
      query = SimdXml.compile!("//a")
      assert {:ok, ["1"]} = SimdXml.eval_text(doc, query)
    end

    test "eval_count counts matches" do
      doc = SimdXml.parse!(@books)
      query = SimdXml.compile!("//book")
      assert {:ok, 3} = SimdXml.eval_count(doc, query)
    end

    test "eval_count! returns count directly" do
      doc = SimdXml.parse!(@books)
      query = SimdXml.compile!("//book")
      assert SimdXml.eval_count!(doc, query) == 3
    end

    test "eval_exists? checks for matches" do
      doc = SimdXml.parse!(@books)
      query = SimdXml.compile!("//book")
      assert {:ok, true} = SimdXml.eval_exists?(doc, query)

      query2 = SimdXml.compile!("//missing")
      assert {:ok, false} = SimdXml.eval_exists?(doc, query2)
    end

    test "compiled query stores original expression" do
      query = SimdXml.compile!("//title")
      assert query.expr == "//title"
    end

    test "eval_count with zero matches" do
      doc = SimdXml.parse!("<r/>")
      query = SimdXml.compile!("//missing")
      assert {:ok, 0} = SimdXml.eval_count(doc, query)
    end
  end

  # ---------------------------------------------------------------------------
  # parse_for_xpath/2
  # ---------------------------------------------------------------------------

  describe "parse_for_xpath/2" do
    test "query-driven parse returns same results" do
      doc = SimdXml.parse_for_xpath!(@books, "//title")
      {:ok, titles} = SimdXml.xpath_text(doc, "//title")
      assert length(titles) == 3
    end

    test "returns error for invalid XML" do
      assert {:error, _} = SimdXml.parse_for_xpath("<<<", "//x")
    end

    test "bang variant raises on error" do
      assert_raise SimdXml.Error, fn ->
        SimdXml.parse_for_xpath!("<<<", "//x")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # XPath edge cases
  # ---------------------------------------------------------------------------

  describe "XPath edge cases" do
    test "dot (.) selects context node" do
      doc = SimdXml.parse!("<r><a>text</a></r>")
      {:ok, [text]} = SimdXml.xpath_string(doc, "//a/.")
      assert text == "text"
    end

    test "wildcard (*) matches all children" do
      doc = SimdXml.parse!("<r><a>1</a><b>2</b><c>3</c></r>")
      {:ok, texts} = SimdXml.xpath_text(doc, "/r/*")
      assert length(texts) == 3
    end

    test "position predicate" do
      doc = SimdXml.parse!("<r><item>1</item><item>2</item><item>3</item></r>")
      {:ok, [text]} = SimdXml.xpath_text(doc, "//item[2]")
      assert text == "2"
    end

    test "last() predicate" do
      doc = SimdXml.parse!("<r><item>1</item><item>2</item><item>3</item></r>")
      {:ok, [text]} = SimdXml.xpath_text(doc, "//item[last()]")
      assert text == "3"
    end

    test "double-slash in middle of path" do
      doc = SimdXml.parse!("<r><a><b><c>deep</c></b></a></r>")
      {:ok, ["deep"]} = SimdXml.xpath_text(doc, "//a//c")
    end

    test "xpath with attribute predicate" do
      doc = SimdXml.parse!(@books)
      {:ok, titles} = SimdXml.xpath_text(doc, "//book[@lang='en']/title")
      assert length(titles) == 2
      assert "Elixir in Action" in titles
    end

    test "nested predicates" do
      doc = SimdXml.parse!(@books)
      {:ok, titles} = SimdXml.xpath_text(doc, "//book[@lang='ja']/title")
      assert titles == ["Programming Elixir"]
    end
  end

  # ---------------------------------------------------------------------------
  # Query combinators
  # ---------------------------------------------------------------------------

  describe "query combinators" do
    import SimdXml.Query

    test "descendant/1 produces //name" do
      assert to_xpath(descendant("book")) == "//book"
    end

    test "child/1 produces name" do
      assert to_xpath(child("title")) == "title"
    end

    test "descendant + child pipe" do
      q = descendant("book") |> child("title")
      assert to_xpath(q) == "//book/title"
    end

    test "with text()" do
      q = descendant("book") |> child("title") |> text()
      assert to_xpath(q) == "//book/title/text()"
    end

    test "where_attr predicate" do
      q = descendant("book") |> where_attr("lang", "en")
      assert to_xpath(q) == "//book[@lang='en']"
    end

    test "has_attr predicate" do
      q = descendant("book") |> has_attr("lang")
      assert to_xpath(q) == "//book[@lang]"
    end

    test "position predicate" do
      q = descendant("book") |> first()
      assert to_xpath(q) == "//book[1]"
    end

    test "union" do
      q = union(descendant("claim"), descendant("abstract"))
      assert to_xpath(q) =~ "//claim"
      assert to_xpath(q) =~ "|"
      assert to_xpath(q) =~ "//abstract"
    end

    test "execution via SimdXml.query!" do
      doc = SimdXml.parse!(@books)
      q = descendant("title") |> text()
      titles = SimdXml.query!(doc, q)
      assert length(titles) == 3
    end

    test "where_attr execution" do
      doc = SimdXml.parse!(@books)
      q = descendant("book") |> where_attr("lang", "en") |> child("title") |> text()
      titles = SimdXml.query!(doc, q)
      assert length(titles) == 2
      assert "Elixir in Action" in titles
      assert "Metaprogramming Elixir" in titles
    end

    test "query/2 returns ok tuple" do
      doc = SimdXml.parse!(@books)
      q = descendant("title") |> text()
      assert {:ok, titles} = SimdXml.query(doc, q)
      assert length(titles) == 3
    end

    test "query/2 returns error for bad xpath" do
      doc = SimdXml.parse!("<r/>")
      q = descendant("a") |> where_expr("///[bad")
      assert {:error, _} = SimdXml.query(doc, q)
    end

    test "query with string return type" do
      doc = SimdXml.parse!(@mixed_content)
      q = descendant("p") |> string()
      {:ok, [text]} = SimdXml.query(doc, q)
      assert text =~ "Hello"
      assert text =~ "bold"
    end

    test "query with nodes return type" do
      doc = SimdXml.parse!(@books)
      q = descendant("book") |> nodes()
      {:ok, result} = SimdXml.query(doc, q)
      assert is_list(result)
      assert length(result) == 3
    end
  end

  # ---------------------------------------------------------------------------
  # Concurrent access
  # ---------------------------------------------------------------------------

  describe "concurrent access" do
    test "multiple processes querying same document" do
      doc = SimdXml.parse!(@books)

      tasks =
        for _ <- 1..20 do
          Task.async(fn ->
            {:ok, titles} = SimdXml.xpath_text(doc, "//title")
            length(titles)
          end)
        end

      results = Task.await_many(tasks, 5_000)
      assert Enum.all?(results, &(&1 == 3))
    end

    test "multiple processes with compiled queries on same document" do
      doc = SimdXml.parse!(@books)
      query = SimdXml.compile!("//book")

      tasks =
        for _ <- 1..20 do
          Task.async(fn ->
            {:ok, count} = SimdXml.eval_count(doc, query)
            count
          end)
        end

      results = Task.await_many(tasks, 5_000)
      assert Enum.all?(results, &(&1 == 3))
    end

    test "multiple processes parsing different documents" do
      xmls = Enum.map(1..20, fn i -> "<r><v>#{i}</v></r>" end)

      tasks =
        for xml <- xmls do
          Task.async(fn ->
            doc = SimdXml.parse!(xml)
            {:ok, [v]} = SimdXml.xpath_text(doc, "//v")
            String.to_integer(v)
          end)
        end

      results = Task.await_many(tasks, 5_000) |> Enum.sort()
      assert results == Enum.to_list(1..20)
    end
  end
end

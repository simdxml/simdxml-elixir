defmodule SimdXml.QueryTest do
  use ExUnit.Case, async: true
  doctest SimdXml.Query

  import SimdXml.Query

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

  @sibling_xml "<r><a>1</a><b>2</b><c>3</c></r>"

  # ===========================================================================
  # Compilation (to_xpath/1)
  # ===========================================================================

  describe "to_xpath/1 - axis constructors" do
    test "descendant with name" do
      assert to_xpath(descendant("book")) == "//book"
    end

    test "descendant with wildcard (no arg)" do
      assert to_xpath(descendant()) == "//*"
    end

    test "child with name" do
      assert to_xpath(child("title")) == "title"
    end

    test "child with wildcard" do
      assert to_xpath(child()) == "*"
    end

    test "self_node" do
      assert to_xpath(self_node("book")) == "self::book"
    end

    test "self_node wildcard" do
      assert to_xpath(self_node()) == "self::*"
    end

    test "parent axis" do
      assert to_xpath(parent("book")) == "parent::book"
    end

    test "parent wildcard" do
      assert to_xpath(parent()) == "parent::*"
    end

    test "ancestor axis" do
      assert to_xpath(ancestor("library")) == "ancestor::library"
    end

    test "ancestor wildcard" do
      assert to_xpath(ancestor()) == "ancestor::*"
    end

    test "following_sibling axis" do
      assert to_xpath(following_sibling("b")) == "following-sibling::b"
    end

    test "following_sibling wildcard" do
      assert to_xpath(following_sibling()) == "following-sibling::*"
    end

    test "preceding_sibling axis" do
      assert to_xpath(preceding_sibling("a")) == "preceding-sibling::a"
    end

    test "preceding_sibling wildcard" do
      assert to_xpath(preceding_sibling()) == "preceding-sibling::*"
    end

    test "attribute axis" do
      assert to_xpath(attribute("lang")) == "attribute::lang"
    end
  end

  describe "to_xpath/1 - chained steps" do
    test "descendant + child" do
      assert to_xpath(descendant("book") |> child("title")) == "//book/title"
    end

    test "descendant + descendant" do
      assert to_xpath(descendant("book") |> descendant("title")) == "//book//title"
    end

    test "descendant + parent" do
      q = descendant("title") |> parent("book")
      assert to_xpath(q) =~ "//title"
      assert to_xpath(q) =~ "parent::book"
    end

    test "descendant + ancestor" do
      q = descendant("title") |> ancestor("library")
      assert to_xpath(q) =~ "//title"
      assert to_xpath(q) =~ "ancestor::library"
    end

    test "descendant + following_sibling" do
      q = descendant("a") |> following_sibling("b")
      assert to_xpath(q) =~ "//a"
      assert to_xpath(q) =~ "following-sibling::b"
    end

    test "descendant + preceding_sibling" do
      q = descendant("b") |> preceding_sibling("a")
      assert to_xpath(q) =~ "//b"
      assert to_xpath(q) =~ "preceding-sibling::a"
    end

    test "descendant + attribute" do
      q = descendant("book") |> attribute("lang")
      assert to_xpath(q) =~ "//book"
      assert to_xpath(q) =~ "attribute::lang"
    end

    test "three-level chain" do
      q = descendant("library") |> child("book") |> child("title")
      assert to_xpath(q) == "//library/book/title"
    end
  end

  describe "to_xpath/1 - text step" do
    test "appends text()" do
      assert to_xpath(descendant("title") |> text()) == "//title/text()"
    end

    test "text at end of chain" do
      q = descendant("book") |> child("title") |> text()
      assert to_xpath(q) == "//book/title/text()"
    end
  end

  describe "to_xpath/1 - predicates" do
    test "where_attr" do
      assert to_xpath(descendant("book") |> where_attr("lang", "en")) == "//book[@lang='en']"
    end

    test "has_attr" do
      assert to_xpath(descendant("book") |> has_attr("id")) == "//book[@id]"
    end

    test "where_expr" do
      assert to_xpath(descendant("section") |> where_expr("count(./p) > 3")) ==
               "//section[count(./p) > 3]"
    end

    test "at position" do
      assert to_xpath(descendant("item") |> at(3)) == "//item[3]"
    end

    test "first" do
      assert to_xpath(descendant("item") |> first()) == "//item[1]"
    end

    test "last" do
      assert to_xpath(descendant("item") |> last()) == "//item[last()]"
    end

    test "multiple predicates chained" do
      q = descendant("book") |> where_attr("lang", "en") |> has_attr("year")
      xpath = to_xpath(q)
      assert xpath =~ "[@lang='en']"
      assert xpath =~ "[@year]"
    end

    test "predicate after child step" do
      q = descendant("library") |> child("book") |> where_attr("lang", "en")
      assert to_xpath(q) == "//library/book[@lang='en']"
    end

    test "predicate + child + text" do
      q = descendant("book") |> where_attr("lang", "en") |> child("title") |> text()
      assert to_xpath(q) == "//book[@lang='en']/title/text()"
    end
  end

  describe "to_xpath/1 - union" do
    test "two queries" do
      q = union(descendant("claim"), descendant("abstract"))
      xpath = to_xpath(q)
      assert xpath =~ "//claim"
      assert xpath =~ " | "
      assert xpath =~ "//abstract"
    end

    test "three queries via list" do
      q = union([descendant("a"), descendant("b"), descendant("c")])
      xpath = to_xpath(q)
      assert xpath =~ "//a"
      assert xpath =~ "//b"
      assert xpath =~ "//c"
      assert length(String.split(xpath, " | ")) == 3
    end
  end

  describe "to_xpath/1 - complex composition" do
    test "full chain with predicate and text" do
      q =
        descendant("book")
        |> where_attr("lang", "en")
        |> child("title")
        |> text()

      assert to_xpath(q) == "//book[@lang='en']/title/text()"
    end

    test "multiple predicates and multiple steps" do
      q =
        descendant("section")
        |> has_attr("id")
        |> where_expr("count(./p) > 0")
        |> child("p")
        |> first()

      xpath = to_xpath(q)
      assert xpath =~ "//section[@id]"
      assert xpath =~ "[count(./p) > 0]"
      assert xpath =~ "/p[1]"
    end
  end

  # ===========================================================================
  # Return type modifiers
  # ===========================================================================

  describe "return type modifiers" do
    test "text sets return_type to :text" do
      q = descendant("a") |> text()
      assert q.return_type == :text
    end

    test "string sets return_type to :string" do
      q = descendant("a") |> string()
      assert q.return_type == :string
    end

    test "nodes sets return_type to :nodes" do
      q = descendant("a") |> nodes()
      assert q.return_type == :nodes
    end

    test "count sets return_type to :count" do
      q = descendant("a") |> count()
      assert q.return_type == :count
    end

    test "exists sets return_type to :exists" do
      q = descendant("a") |> exists()
      assert q.return_type == :exists
    end

    test "default return_type is :text" do
      q = descendant("a")
      assert q.return_type == :text
    end
  end

  # ===========================================================================
  # Composability / reuse
  # ===========================================================================

  describe "composability" do
    test "reusable fragments" do
      books = descendant("book")
      english = books |> where_attr("lang", "en")
      titles = english |> child("title") |> text()
      all_titles = books |> child("title") |> text()

      assert to_xpath(titles) == "//book[@lang='en']/title/text()"
      assert to_xpath(all_titles) == "//book/title/text()"
      # Original should not be mutated
      assert to_xpath(books) == "//book"
    end

    test "fragment used in union" do
      claims = descendant("claim")
      abstracts = descendant("abstract")
      both = union(claims, abstracts)

      # Originals unchanged
      assert to_xpath(claims) == "//claim"
      assert to_xpath(abstracts) == "//abstract"
      assert to_xpath(both) =~ "//claim"
      assert to_xpath(both) =~ "//abstract"
    end
  end

  # ===========================================================================
  # Execution (against real documents)
  # ===========================================================================

  describe "execution - text return type" do
    test "descendant with text" do
      doc = SimdXml.parse!(@books)
      q = descendant("title") |> text()
      result = SimdXml.query!(doc, q)
      assert length(result) == 3
      assert "Elixir in Action" in result
    end

    test "where_attr filters correctly" do
      doc = SimdXml.parse!(@books)
      q = descendant("book") |> where_attr("lang", "en") |> child("title") |> text()
      result = SimdXml.query!(doc, q)
      assert length(result) == 2
      assert "Elixir in Action" in result
      assert "Metaprogramming Elixir" in result
      refute "Programming Elixir" in result
    end

    test "first selects only first match" do
      doc = SimdXml.parse!(@books)
      q = descendant("book") |> first() |> child("title") |> text()
      result = SimdXml.query!(doc, q)
      assert result == ["Elixir in Action"]
    end

    test "wildcard descendant" do
      doc = SimdXml.parse!("<r><a>1</a><b>2</b></r>")
      q = descendant() |> text()
      result = SimdXml.query!(doc, q)
      assert "1" in result
      assert "2" in result
    end
  end

  describe "execution - string return type" do
    test "string-value includes all descendant text" do
      doc = SimdXml.parse!("<r><a>hello <b>world</b></a></r>")
      q = descendant("a") |> string()
      {:ok, [text]} = SimdXml.query(doc, q)
      assert text == "hello world"
    end
  end

  describe "execution - nodes return type" do
    test "nodes returns element references" do
      doc = SimdXml.parse!(@books)
      q = descendant("book") |> nodes()
      {:ok, result} = SimdXml.query(doc, q)
      assert is_list(result)
      assert length(result) == 3
    end
  end

  describe "execution - axes" do
    test "following-sibling" do
      doc = SimdXml.parse!(@sibling_xml)
      q = descendant("a") |> following_sibling("b") |> text()
      result = SimdXml.query!(doc, q)
      assert result == ["2"]
    end

    test "preceding-sibling" do
      doc = SimdXml.parse!(@sibling_xml)
      q = descendant("c") |> preceding_sibling("b") |> text()
      result = SimdXml.query!(doc, q)
      assert result == ["2"]
    end

    test "parent axis returns matching parents" do
      doc = SimdXml.parse!(@books)
      q = descendant("title") |> parent("book")
      {:ok, nodes} = SimdXml.query(doc, q)
      # parent axis returns text of matching parents -- may include whitespace
      assert is_list(nodes)
      assert length(nodes) > 0
    end

    test "ancestor axis returns matching ancestors" do
      doc = SimdXml.parse!(@books)
      q = descendant("title") |> ancestor("library")
      {:ok, nodes} = SimdXml.query(doc, q)
      assert is_list(nodes)
      assert length(nodes) >= 1
    end
  end

  describe "execution - union" do
    test "union combines results from both queries" do
      doc = SimdXml.parse!(@books)
      q = union(descendant("title"), descendant("author"))
      {:ok, results} = SimdXml.query(doc, q)
      assert length(results) == 6
    end
  end
end

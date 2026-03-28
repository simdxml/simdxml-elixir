defmodule SimdXml.AdversarialTest do
  use ExUnit.Case, async: true

  @moduledoc """
  Adversarial and stress tests for simdxml.

  These tests ensure the parser handles malicious, malformed, and
  pathologically large inputs without crashing, hanging, or consuming
  unbounded resources.
  """

  # ---------------------------------------------------------------------------
  # Billion laughs / entity expansion
  # ---------------------------------------------------------------------------

  describe "billion laughs defense" do
    test "entity expansion is not performed (no XXE)" do
      # Classic billion laughs payload -- simdxml should not expand entities
      xml = """
      <?xml version="1.0"?>
      <!DOCTYPE lolz [
        <!ENTITY lol "lol">
        <!ENTITY lol2 "&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;&lol;">
        <!ENTITY lol3 "&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;&lol2;">
      ]>
      <root>&lol3;</root>
      """

      # Should either error out or parse without expanding
      case SimdXml.parse(xml) do
        {:error, _} ->
          # Correctly rejected
          :ok

        {:ok, doc} ->
          # Parsed but did not expand -- text should not be massive
          {:ok, texts} = SimdXml.xpath_text(doc, "//root")

          case texts do
            [] -> :ok
            [text] -> assert byte_size(text) < 10_000
          end
      end
    end

    test "DTD with external entity reference is safe" do
      xml = """
      <?xml version="1.0"?>
      <!DOCTYPE foo [
        <!ENTITY xxe SYSTEM "file:///etc/passwd">
      ]>
      <root>&xxe;</root>
      """

      case SimdXml.parse(xml) do
        {:error, _} ->
          :ok

        {:ok, doc} ->
          {:ok, texts} = SimdXml.xpath_text(doc, "//root")
          # Must not contain file contents
          for text <- texts do
            refute text =~ "root:"
          end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Very large attribute values
  # ---------------------------------------------------------------------------

  describe "large attribute values" do
    test "1MB attribute value" do
      big_value = String.duplicate("a", 1_000_000)
      xml = ~s(<root attr="#{big_value}"/>)

      case SimdXml.parse(xml) do
        {:ok, doc} ->
          root = SimdXml.Document.root(doc)
          val = SimdXml.Element.get(root, "attr")
          assert byte_size(val) == 1_000_000

        {:error, _} ->
          # Acceptable to reject very large attributes
          :ok
      end
    end

    test "large text content (1MB)" do
      big_text = String.duplicate("x", 1_000_000)
      xml = "<root>#{big_text}</root>"

      case SimdXml.parse(xml) do
        {:ok, doc} ->
          {:ok, [text]} = SimdXml.xpath_text(doc, "//root")
          assert byte_size(text) == 1_000_000

        {:error, _} ->
          :ok
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Deep nesting
  # ---------------------------------------------------------------------------

  describe "deep nesting" do
    test "1000 levels deep" do
      open = Enum.map(1..1000, fn i -> "<l#{i}>" end) |> Enum.join()
      close = Enum.map(1000..1//-1, fn i -> "</l#{i}>" end) |> Enum.join()
      xml = open <> "<leaf>deep</leaf>" <> close

      case SimdXml.parse(xml) do
        {:ok, doc} ->
          # Parsing succeeded -- xpath may or may not find deeply nested element
          {:ok, texts} = SimdXml.xpath_text(doc, "//leaf")
          assert texts == ["deep"] or texts == []

        {:error, _} ->
          # Acceptable to reject extremely deep nesting
          :ok
      end
    end

    @tag :slow
    test "5000 levels deep does not crash" do
      open = Enum.map(1..5000, fn i -> "<l#{i}>" end) |> Enum.join()
      close = Enum.map(5000..1//-1, fn i -> "</l#{i}>" end) |> Enum.join()
      xml = open <> "text" <> close

      # Must not crash -- error is acceptable
      result = SimdXml.parse(xml)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  # ---------------------------------------------------------------------------
  # Binary / null bytes
  # ---------------------------------------------------------------------------

  describe "binary / null bytes" do
    test "null bytes in input" do
      xml = "<root>\x00\x00\x00</root>"

      case SimdXml.parse(xml) do
        {:error, _} -> :ok
        {:ok, _doc} -> :ok
      end
    end

    test "mixed null and valid content" do
      xml = "<root><a>hello\x00world</a></root>"

      case SimdXml.parse(xml) do
        {:error, _} ->
          :ok

        {:ok, doc} ->
          {:ok, texts} = SimdXml.xpath_text(doc, "//a")
          # Parsing succeeded - just verify no crash
          assert is_list(texts)
      end
    end

    test "non-UTF8 bytes" do
      xml = "<root>" <> <<0xFF, 0xFE>> <> "</root>"

      case SimdXml.parse(xml) do
        {:error, _} -> :ok
        {:ok, _doc} -> :ok
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Pathological XPath
  # ---------------------------------------------------------------------------

  describe "pathological XPath expressions" do
    test "very long XPath expression" do
      # 100 nested descendant steps
      long_xpath = Enum.map(1..100, fn _ -> "a" end) |> Enum.join("//")
      long_xpath = "//" <> long_xpath
      doc = SimdXml.parse!("<root><a>text</a></root>")

      # Should not hang -- error or empty result is fine
      case SimdXml.xpath_text(doc, long_xpath) do
        {:ok, _} -> :ok
        {:error, _} -> :ok
      end
    end

    test "many predicates" do
      xpath = "//a" <> String.duplicate("[@x='y']", 50)
      doc = SimdXml.parse!("<root><a x='y'>text</a></root>")

      case SimdXml.xpath_text(doc, xpath) do
        {:ok, _} -> :ok
        {:error, _} -> :ok
      end
    end

    test "deeply nested function calls" do
      # string(string(string(...(//a)...)))
      inner = "//a"
      xpath = Enum.reduce(1..20, inner, fn _, acc -> "string(#{acc})" end)
      doc = SimdXml.parse!("<root><a>text</a></root>")

      case SimdXml.Document.eval(doc, xpath) do
        {:ok, _} -> :ok
        {:error, _} -> :ok
      end
    end

    test "invalid xpath does not crash" do
      doc = SimdXml.parse!("<root/>")

      bad_xpaths = [
        "",
        "///",
        "[[[",
        "//a[",
        "//a[@",
        "//a[999999999999999999999]",
        String.duplicate("/", 1000),
        "ancestor-or-self::*[self::*[self::*]]"
      ]

      for xpath <- bad_xpaths do
        result = SimdXml.xpath_text(doc, xpath)

        assert match?({:ok, _}, result) or match?({:error, _}, result),
               "XPath #{inspect(xpath)} caused unexpected result: #{inspect(result)}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Empty tags everywhere
  # ---------------------------------------------------------------------------

  describe "empty tags" do
    test "document of only self-closing tags" do
      children = Enum.map(1..200, fn _ -> "<item/>" end) |> Enum.join()
      xml = "<r>" <> children <> "</r>"
      {:ok, doc} = SimdXml.parse(xml)
      {:ok, items} = SimdXml.xpath_text(doc, "//item")
      assert items == [] or length(items) == 200
    end

    test "empty root self-closing" do
      {:ok, doc} = SimdXml.parse("<root/>")
      root = SimdXml.Document.root(doc)
      assert root.tag == "root"
      assert SimdXml.Element.children(root) == []
      assert SimdXml.Element.text(root) == nil
    end

    test "nested self-closing" do
      xml = "<a><b/><c><d/></c></a>"
      {:ok, doc} = SimdXml.parse(xml)
      root = SimdXml.Document.root(doc)
      children = SimdXml.Element.children(root)
      assert length(children) == 2
    end
  end

  # ---------------------------------------------------------------------------
  # Maximum tag name length
  # ---------------------------------------------------------------------------

  describe "long tag names" do
    test "very long tag name (10KB)" do
      tag = String.duplicate("a", 10_000)
      xml = "<#{tag}>content</#{tag}>"

      case SimdXml.parse(xml) do
        {:ok, doc} ->
          root = SimdXml.Document.root(doc)
          assert root.tag == tag

        {:error, _} ->
          :ok
      end
    end

    test "long attribute name" do
      attr = String.duplicate("x", 5_000)
      xml = ~s(<root #{attr}="val"/>)

      case SimdXml.parse(xml) do
        {:ok, doc} ->
          root = SimdXml.Document.root(doc)
          assert SimdXml.Element.get(root, attr) == "val"

        {:error, _} ->
          :ok
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Wide documents (stress)
  # ---------------------------------------------------------------------------

  describe "wide documents" do
    test "element with 10000 children" do
      children = Enum.map(1..10_000, fn i -> "<item>#{i}</item>" end) |> Enum.join()
      xml = "<root>" <> children <> "</root>"

      {:ok, doc} = SimdXml.parse(xml)
      {:ok, items} = SimdXml.xpath_text(doc, "//item")
      assert length(items) == 10_000
    end
  end

  # ---------------------------------------------------------------------------
  # Concurrent stress
  # ---------------------------------------------------------------------------

  describe "concurrent stress" do
    test "50 concurrent parse + query operations" do
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            xml = "<r><v>#{i}</v></r>"
            doc = SimdXml.parse!(xml)
            {:ok, [text]} = SimdXml.xpath_text(doc, "//v")
            String.to_integer(text)
          end)
        end

      results = Task.await_many(tasks, 10_000)
      assert Enum.sort(results) == Enum.to_list(1..50)
    end
  end
end

defmodule SimdXml do
  @moduledoc """
  SIMD-accelerated XML parsing with full XPath 1.0 support.

  SimdXml parses XML into a flat structural index (~16 bytes per tag) using SIMD
  instructions, then evaluates XPath expressions against it using array
  operations. There is no DOM tree, no atom creation, and no XXE vulnerabilities.

  ## Quick start

      doc = SimdXml.parse!("<books><book><title>Elixir</title></book></books>")
      SimdXml.xpath_text!(doc, "//title")
      #=> ["Elixir"]

  ## Compiled queries

  For repeated queries across many documents, compile the XPath once and reuse it.
  The compiled query is a NIF resource that can be shared across processes safely:

      query = SimdXml.compile!("//title")
      SimdXml.eval_text!(doc, query)

  See `SimdXml.XPath` for details on the compile-once-run-many pattern.

  ## Query combinators

  Build queries programmatically with `SimdXml.Query` instead of writing XPath
  strings by hand:

      import SimdXml.Query

      query = descendant("book") |> child("title") |> text()
      SimdXml.query!(doc, query)

  See `SimdXml.Query` for the full combinator API.

  ## Element navigation

  Navigate the document tree through immutable element references. Elements
  implement `Enumerable`, so standard `Enum` functions work on child elements:

      root = SimdXml.Document.root(doc)
      Enum.map(root, & &1.tag)  # child element tags

  See `SimdXml.Element` for the navigation API.

  ## Batch processing

  Process thousands of documents with a single compiled query. Bloom filter
  prescanning skips documents that cannot match:

      query = SimdXml.compile!("//claim")
      SimdXml.Batch.eval_text_bloom(xml_binaries, query)

  See `SimdXml.Batch` for batch operations.

  ## Quick grep mode

  For simple `//tagname` extraction at near-memory-bandwidth speed, skip the
  structural index entirely:

      scanner = SimdXml.Quick.new("claim")
      SimdXml.Quick.extract_first(scanner, xml)

  See `SimdXml.Quick` for the grep-mode API.

  ## Related modules

    * `SimdXml.Document` - parsed document handle and XPath evaluation
    * `SimdXml.Element` - element navigation and attribute access
    * `SimdXml.XPath` - compiled XPath expressions
    * `SimdXml.Query` - composable query builders
    * `SimdXml.Result` - convenience accessors (`one/2`, `fetch/2`)
    * `SimdXml.Batch` - multi-document batch processing
    * `SimdXml.Quick` - grep-mode fast path
    * `SimdXml.Error` - exception type for bang functions
  """

  alias SimdXml.{Document, Native, Query, XPath}

  # ---------------------------------------------------------------------------
  # Parsing
  # ---------------------------------------------------------------------------

  @doc """
  Parses an XML binary into a document.

  Returns `{:ok, document}` on success, or `{:error, reason}` if the XML is
  malformed. The returned `SimdXml.Document` holds an immutable structural index
  on the Rust side. It is reference-counted and garbage-collected by the BEAM --
  no manual cleanup is needed.

  ## Examples

      iex> {:ok, doc} = SimdXml.parse("<root/>")
      iex> SimdXml.Document.tag_count(doc)
      1

      iex> {:error, _reason} = SimdXml.parse("not xml <<<")
  """
  @spec parse(binary()) :: {:ok, Document.t()} | {:error, String.t()}
  def parse(xml) when is_binary(xml) do
    case Native.parse(xml) do
      {:ok, ref} -> {:ok, %Document{ref: ref}}
      {:error, _} = err -> err
    end
  end

  @doc """
  Parses an XML binary into a document, raising on error.

  Same as `parse/1` but returns the document directly or raises
  `SimdXml.Error` if parsing fails.

  ## Examples

      iex> doc = SimdXml.parse!("<root><child/></root>")
      iex> SimdXml.Document.tag_count(doc)
      3
  """
  @spec parse!(binary()) :: Document.t()
  def parse!(xml) do
    case parse(xml) do
      {:ok, doc} -> doc
      {:error, reason} -> raise SimdXml.Error, reason
    end
  end

  @doc """
  Parses with query-driven optimization.

  Only indexes tags relevant to the given XPath expression. This is faster than
  `parse/1` when you know the query upfront and the document is large, because
  irrelevant structural data is never materialized.

  ## Examples

      iex> {:ok, doc} = SimdXml.parse_for_xpath("<r><a>1</a><b>2</b></r>", "//a")
      iex> SimdXml.xpath_text!(doc, "//a")
      ["1"]
  """
  @spec parse_for_xpath(binary(), String.t()) :: {:ok, Document.t()} | {:error, String.t()}
  def parse_for_xpath(xml, xpath) when is_binary(xml) and is_binary(xpath) do
    case Native.parse_for_xpath(xml, xpath) do
      {:ok, ref} -> {:ok, %Document{ref: ref}}
      {:error, _} = err -> err
    end
  end

  @doc """
  Parses with query-driven optimization, raising on error.

  Same as `parse_for_xpath/2` but returns the document directly or raises
  `SimdXml.Error`.

  ## Examples

      iex> doc = SimdXml.parse_for_xpath!("<r><title>Hi</title></r>", "//title")
      iex> SimdXml.xpath_text!(doc, "//title")
      ["Hi"]
  """
  @spec parse_for_xpath!(binary(), String.t()) :: Document.t()
  def parse_for_xpath!(xml, xpath) do
    case parse_for_xpath(xml, xpath) do
      {:ok, doc} -> doc
      {:error, reason} -> raise SimdXml.Error, reason
    end
  end

  # ---------------------------------------------------------------------------
  # XPath (string expressions)
  # ---------------------------------------------------------------------------

  @doc """
  Evaluates an XPath expression, returning direct child text of each match.

  This returns only the immediate text content of matched elements. For
  `<p>Hello <b>world</b></p>`, querying for `//p` returns `["Hello "]` because
  only the direct text child is included. Use `xpath_string/2` if you need all
  descendant text concatenated.

  ## Examples

      iex> doc = SimdXml.parse!("<r><a>1</a><b>2</b></r>")
      iex> SimdXml.xpath_text(doc, "//a")
      {:ok, ["1"]}

      iex> doc = SimdXml.parse!("<r><a>1</a><a>2</a></r>")
      iex> SimdXml.xpath_text(doc, "//a")
      {:ok, ["1", "2"]}
  """
  @spec xpath_text(Document.t(), String.t()) :: {:ok, [String.t()]} | {:error, String.t()}
  def xpath_text(%Document{} = doc, expr), do: Document.xpath_text(doc, expr)

  @doc """
  Evaluates an XPath expression for direct child text, raising on error.

  Same as `xpath_text/2` but returns the list directly or raises
  `SimdXml.Error`.

  ## Examples

      iex> doc = SimdXml.parse!("<r><a>1</a><b>2</b></r>")
      iex> SimdXml.xpath_text!(doc, "//b")
      ["2"]

      iex> doc = SimdXml.parse!("<r><a>1</a></r>")
      iex> SimdXml.xpath_text!(doc, "//missing")
      []
  """
  @spec xpath_text!(Document.t(), String.t()) :: [String.t()]
  def xpath_text!(%Document{} = doc, expr) do
    case xpath_text(doc, expr) do
      {:ok, results} -> results
      {:error, reason} -> raise SimdXml.Error, reason
    end
  end

  @doc """
  Evaluates an XPath expression, returning the string-value of each match.

  The string-value is all descendant text concatenated, which matches XPath's
  `string()` semantics. For `<p>Hello <b>world</b></p>`, querying for `//p`
  returns `["Hello world"]`.

  Use this instead of `xpath_text/2` when elements contain mixed content
  (text interspersed with child elements).

  ## Examples

      iex> doc = SimdXml.parse!("<p>Hello <b>world</b></p>")
      iex> SimdXml.xpath_string(doc, "//p")
      {:ok, ["Hello world"]}
  """
  @spec xpath_string(Document.t(), String.t()) :: {:ok, [String.t()]} | {:error, String.t()}
  def xpath_string(%Document{} = doc, expr), do: Document.xpath_string(doc, expr)

  @doc """
  Evaluates an XPath expression for string-values, raising on error.

  Same as `xpath_string/2` but returns the list directly or raises
  `SimdXml.Error`.

  ## Examples

      iex> doc = SimdXml.parse!("<p>Hello <b>world</b></p>")
      iex> SimdXml.xpath_string!(doc, "//p")
      ["Hello world"]
  """
  @spec xpath_string!(Document.t(), String.t()) :: [String.t()]
  def xpath_string!(%Document{} = doc, expr) do
    case xpath_string(doc, expr) do
      {:ok, results} -> results
      {:error, reason} -> raise SimdXml.Error, reason
    end
  end

  # ---------------------------------------------------------------------------
  # Compiled queries
  # ---------------------------------------------------------------------------

  @doc """
  Compiles an XPath expression for reuse across documents.

  Returns `{:ok, xpath}` on success, or `{:error, reason}` if the expression
  is invalid. Compiled queries avoid re-parsing the XPath string on every
  evaluation and can be shared safely across processes.

  See `SimdXml.XPath` for more on the compile-once-run-many pattern.

  ## Examples

      iex> {:ok, query} = SimdXml.compile("//title")
      iex> query.expr
      "//title"

      iex> {:error, _reason} = SimdXml.compile("///invalid[")
  """
  @spec compile(String.t()) :: {:ok, XPath.t()} | {:error, String.t()}
  def compile(expr) when is_binary(expr) do
    case Native.compile_xpath(expr) do
      {:ok, ref} -> {:ok, %XPath{ref: ref, expr: expr}}
      {:error, _} = err -> err
    end
  end

  @doc """
  Compiles an XPath expression, raising on error.

  Same as `compile/1` but returns the `SimdXml.XPath` directly or raises
  `SimdXml.Error`.

  ## Examples

      iex> query = SimdXml.compile!("//title")
      iex> query.expr
      "//title"
  """
  @spec compile!(String.t()) :: XPath.t()
  def compile!(expr) do
    case compile(expr) do
      {:ok, xpath} -> xpath
      {:error, reason} -> raise SimdXml.Error, reason
    end
  end

  @doc """
  Evaluates a compiled XPath, returning direct child text of each match.

  This is the compiled-query equivalent of `xpath_text/2`. Use this when
  running the same query against many documents for best performance.

  ## Examples

      iex> query = SimdXml.compile!("//title")
      iex> doc = SimdXml.parse!("<r><title>Hello</title></r>")
      iex> SimdXml.eval_text(doc, query)
      {:ok, ["Hello"]}
  """
  @spec eval_text(Document.t(), XPath.t()) :: {:ok, [String.t()]} | {:error, String.t()}
  def eval_text(%Document{ref: doc_ref}, %XPath{ref: xpath_ref}) do
    Native.compiled_eval_text(doc_ref, xpath_ref)
  end

  @doc """
  Evaluates a compiled XPath for text, raising on error.

  Same as `eval_text/2` but returns the list directly or raises
  `SimdXml.Error`.

  ## Examples

      iex> query = SimdXml.compile!("//title")
      iex> doc = SimdXml.parse!("<r><title>Hello</title></r>")
      iex> SimdXml.eval_text!(doc, query)
      ["Hello"]
  """
  @spec eval_text!(Document.t(), XPath.t()) :: [String.t()]
  def eval_text!(doc, xpath) do
    case eval_text(doc, xpath) do
      {:ok, results} -> results
      {:error, reason} -> raise SimdXml.Error, reason
    end
  end

  @doc """
  Counts the number of matches for a compiled XPath.

  More efficient than evaluating and counting results, because no text
  extraction occurs.

  ## Examples

      iex> query = SimdXml.compile!("//item")
      iex> doc = SimdXml.parse!("<r><item/><item/><item/></r>")
      iex> SimdXml.eval_count(doc, query)
      {:ok, 3}
  """
  @spec eval_count(Document.t(), XPath.t()) :: {:ok, non_neg_integer()} | {:error, String.t()}
  def eval_count(%Document{ref: doc_ref}, %XPath{ref: xpath_ref}) do
    Native.compiled_eval_count(doc_ref, xpath_ref)
  end

  @doc """
  Counts matches for a compiled XPath, raising on error.

  Same as `eval_count/2` but returns the count directly or raises
  `SimdXml.Error`.

  ## Examples

      iex> query = SimdXml.compile!("//item")
      iex> doc = SimdXml.parse!("<r><item/><item/></r>")
      iex> SimdXml.eval_count!(doc, query)
      2
  """
  @spec eval_count!(Document.t(), XPath.t()) :: non_neg_integer()
  def eval_count!(doc, xpath) do
    case eval_count(doc, xpath) do
      {:ok, count} -> count
      {:error, reason} -> raise SimdXml.Error, reason
    end
  end

  @doc """
  Checks whether a compiled XPath has any matches in the document.

  Short-circuits after the first match, so this is faster than
  `eval_count/2` when you only need a boolean answer.

  ## Examples

      iex> query = SimdXml.compile!("//item")
      iex> doc = SimdXml.parse!("<r><item/></r>")
      iex> SimdXml.eval_exists?(doc, query)
      {:ok, true}

      iex> query = SimdXml.compile!("//missing")
      iex> doc = SimdXml.parse!("<r/>")
      iex> SimdXml.eval_exists?(doc, query)
      {:ok, false}
  """
  @spec eval_exists?(Document.t(), XPath.t()) :: {:ok, boolean()} | {:error, String.t()}
  def eval_exists?(%Document{ref: doc_ref}, %XPath{ref: xpath_ref}) do
    Native.compiled_eval_exists(doc_ref, xpath_ref)
  end

  # ---------------------------------------------------------------------------
  # Query combinator execution
  # ---------------------------------------------------------------------------

  @doc """
  Executes a query combinator against a document.

  The query is compiled to an XPath string via `SimdXml.Query.to_xpath/1` and
  evaluated. The return type depends on the query's `:return_type` setting:

    * `:text` (default) - direct child text via `xpath_text/2`
    * `:string` - string-value (all descendant text) via `xpath_string/2`
    * `:nodes` - element node references
    * `:count` - match count as a number
    * `:exists` - boolean existence check

  ## Examples

      iex> import SimdXml.Query
      iex> doc = SimdXml.parse!("<r><a>1</a><b>2</b></r>")
      iex> SimdXml.query(doc, descendant("a") |> text())
      {:ok, ["1"]}

      iex> import SimdXml.Query
      iex> doc = SimdXml.parse!("<r><a>1</a><a>2</a></r>")
      iex> SimdXml.query!(doc, descendant("a") |> text())
      ["1", "2"]
  """
  @spec query(Document.t(), Query.t()) :: {:ok, term()} | {:error, String.t()}
  def query(%Document{} = doc, %Query{} = q) do
    xpath_str = Query.to_xpath(q)

    case q.return_type do
      :text -> xpath_text(doc, xpath_str)
      :string -> xpath_string(doc, xpath_str)
      :nodes -> Document.xpath_nodes(doc, xpath_str)
      :count -> Document.eval(doc, "count(#{xpath_str})")
      :exists -> Document.eval(doc, "boolean(#{xpath_str})")
    end
  end

  @doc """
  Executes a query combinator, raising on error.

  Same as `query/2` but returns the result directly or raises
  `SimdXml.Error`.

  ## Examples

      iex> import SimdXml.Query
      iex> doc = SimdXml.parse!("<r><a>1</a><b>2</b></r>")
      iex> SimdXml.query!(doc, descendant("a") |> text())
      ["1"]
  """
  @spec query!(Document.t(), Query.t()) :: term()
  def query!(doc, q) do
    case query(doc, q) do
      {:ok, results} -> results
      {:error, reason} -> raise SimdXml.Error, reason
    end
  end
end

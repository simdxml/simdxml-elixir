defmodule SimdXml.Document do
  @moduledoc """
  A parsed XML document backed by a SIMD-accelerated structural index.

  Documents are opaque, immutable references to Rust-side data. The XML bytes
  and structural index (~16 bytes per tag) live in Rust memory, accessed through
  NIF calls. Documents are reference-counted and garbage-collected by the BEAM --
  no manual cleanup is required.

  A `Document` is the entry point for all XML operations: XPath evaluation,
  element navigation, and batch processing all start from a parsed document.

  ## Parsing

  Create documents with `SimdXml.parse/1` or `SimdXml.parse!/1`:

      doc = SimdXml.parse!("<library><book><title>Rust</title></book></library>")

  For query-driven optimization, use `SimdXml.parse_for_xpath/2` which only
  indexes tags relevant to a specific XPath expression.

  ## Examples

      iex> doc = SimdXml.parse!("<library><book><title>Rust</title></book></library>")
      iex> SimdXml.Document.xpath_text(doc, "//title")
      {:ok, ["Rust"]}

      iex> doc = SimdXml.parse!("<r><a>1</a><b>2</b></r>")
      iex> SimdXml.Document.tag_count(doc)
      6

  ## Related modules

    * `SimdXml` - top-level parsing and XPath convenience functions
    * `SimdXml.Element` - element navigation from `root/1`
    * `SimdXml.XPath` - compiled XPath for repeated evaluation
  """

  @enforce_keys [:ref]
  defstruct [:ref]

  @type t :: %__MODULE__{ref: reference()}

  @doc """
  Returns the root element of the document, or `nil` for empty documents.

  The root element is a `SimdXml.Element` struct that you can navigate with
  `SimdXml.Element` functions or iterate with `Enum` (elements implement
  `Enumerable` over their children).

  ## Examples

      iex> doc = SimdXml.parse!("<root><child/></root>")
      iex> root = SimdXml.Document.root(doc)
      iex> root.tag
      "root"

      iex> doc = SimdXml.parse!("<catalog><item>A</item><item>B</item></catalog>")
      iex> root = SimdXml.Document.root(doc)
      iex> Enum.map(root, & &1.tag)
      ["item", "item"]
  """
  @spec root(t()) :: SimdXml.Element.t() | nil
  def root(%__MODULE__{ref: ref}) do
    case SimdXml.Native.document_root(ref) do
      nil -> nil
      tag_idx -> SimdXml.Element.new(ref, tag_idx)
    end
  end

  @doc """
  Returns the number of tags in the structural index.

  This includes open tags, close tags, and self-closing tags. Useful for
  diagnostics and understanding document complexity.

  ## Examples

      iex> doc = SimdXml.parse!("<root/>")
      iex> SimdXml.Document.tag_count(doc)
      1

      iex> doc = SimdXml.parse!("<r><a/><b/></r>")
      iex> SimdXml.Document.tag_count(doc)
      4
  """
  @spec tag_count(t()) :: non_neg_integer()
  def tag_count(%__MODULE__{ref: ref}), do: SimdXml.Native.document_tag_count(ref)

  @doc """
  Evaluates an XPath expression, returning direct child text of each match.

  Only the immediate text children of matched elements are returned. For mixed
  content like `<p>Hello <b>world</b></p>`, querying `//p` returns `["Hello "]`.
  Use `xpath_string/2` if you need all descendant text concatenated.

  ## Examples

      iex> doc = SimdXml.parse!("<r><a>hello</a><b>world</b></r>")
      iex> SimdXml.Document.xpath_text(doc, "//a")
      {:ok, ["hello"]}

      iex> doc = SimdXml.parse!("<r><a>1</a><a>2</a></r>")
      iex> SimdXml.Document.xpath_text(doc, "//a")
      {:ok, ["1", "2"]}
  """
  @spec xpath_text(t(), String.t()) :: {:ok, [String.t()]} | {:error, String.t()}
  def xpath_text(%__MODULE__{ref: ref}, expr) do
    SimdXml.Native.xpath_text(ref, expr)
  end

  @doc """
  Evaluates an XPath expression, returning the string-value of each match.

  The string-value is all descendant text concatenated, matching the XPath
  `string()` semantics. For `<a>hello <b>world</b></a>`, this returns
  `"hello world"`.

  Use this instead of `xpath_text/2` when elements contain mixed content.

  ## Examples

      iex> doc = SimdXml.parse!("<p>Hello <b>world</b></p>")
      iex> SimdXml.Document.xpath_string(doc, "//p")
      {:ok, ["Hello world"]}
  """
  @spec xpath_string(t(), String.t()) :: {:ok, [String.t()]} | {:error, String.t()}
  def xpath_string(%__MODULE__{ref: ref}, expr) do
    SimdXml.Native.xpath_string(ref, expr)
  end

  @doc """
  Evaluates an XPath expression, returning node references.

  Nodes are returned as tagged tuples: `{:element, idx}`, `{:text, idx}`,
  or `{:attribute, idx}`. Use `SimdXml.Element.new/2` to wrap element nodes
  for further navigation.

  This is a lower-level function. Most users should prefer `xpath_text/2` or
  `xpath_string/2`.

  ## Examples

      iex> doc = SimdXml.parse!("<r><a/><b/></r>")
      iex> {:ok, nodes} = SimdXml.Document.xpath_nodes(doc, "/r/*")
      iex> length(nodes)
      2
  """
  @spec xpath_nodes(t(), String.t()) :: {:ok, [tuple()]} | {:error, String.t()}
  def xpath_nodes(%__MODULE__{ref: ref}, expr) do
    SimdXml.Native.xpath_nodes(ref, expr)
  end

  @doc """
  Evaluates a scalar XPath expression (count, boolean, string function).

  Returns tagged results depending on the XPath expression type:

    * `{:number, float}` - for `count()`, `sum()`, numeric expressions
    * `{:string, binary}` - for `string()`, `concat()`, etc.
    * `{:boolean, boolean}` - for `boolean()`, comparison expressions
    * `{:nodeset, [tuple]}` - for node-set expressions

  ## Examples

      iex> doc = SimdXml.parse!("<r><a>hello</a></r>")
      iex> {:ok, _result} = SimdXml.Document.eval(doc, "//a")
  """
  @spec eval(t(), String.t()) :: {:ok, term()} | {:error, String.t()}
  def eval(%__MODULE__{ref: ref}, expr) do
    SimdXml.Native.eval(ref, expr)
  end
end

defimpl Inspect, for: SimdXml.Document do
  def inspect(%SimdXml.Document{ref: ref}, _opts) do
    count = SimdXml.Native.document_tag_count(ref)
    "#SimdXml.Document<tags: #{count}>"
  end
end

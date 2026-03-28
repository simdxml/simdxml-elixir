defmodule SimdXml.Quick do
  @moduledoc """
  Grep-mode fast path for simple `//tagname` extraction.

  Skips structural indexing entirely -- scans raw bytes with SIMD-accelerated
  `memchr` at near-memory-bandwidth speed. Use this when you need a single tag
  from many documents and do not need XPath predicates, attributes, or complex
  navigation.

  ## When to use Quick vs full parsing

    * **Use Quick** for simple tag extraction (`//tagname`) across many
      documents where speed is paramount. Quick scanners cannot evaluate
      predicates, navigate axes, or handle namespaces.
    * **Use `SimdXml.Batch`** when you need XPath predicates or more complex
      expressions but still want batch processing.
    * **Use `SimdXml.parse/1`** when you need full XPath or element navigation.

  ## Scanner lifecycle

  Create a scanner once with `new/1` and reuse it across documents. The scanner
  compiles the tag name into an optimized byte pattern -- this is the only
  allocation. All extraction functions are zero-allocation on the Elixir side.

  ## Limitations

  `extract_first/2` returns `nil` for elements that contain nested child
  elements. If you encounter this, fall back to the full parser. The scanner
  only handles simple text content between open and close tags.

  ## Examples

      iex> scanner = SimdXml.Quick.new("title")
      iex> SimdXml.Quick.extract_first(scanner, "<r><title>Hello</title></r>")
      "Hello"

      iex> scanner = SimdXml.Quick.new("title")
      iex> SimdXml.Quick.exists?(scanner, "<r><title>Hello</title></r>")
      true

      iex> scanner = SimdXml.Quick.new("missing")
      iex> SimdXml.Quick.exists?(scanner, "<r><title>Hello</title></r>")
      false

      iex> scanner = SimdXml.Quick.new("item")
      iex> SimdXml.Quick.count(scanner, "<r><item/><item/><item/></r>")
      3

  ## Related modules

    * `SimdXml.Batch` - batch processing with full XPath support
    * `SimdXml` - full parsing and XPath evaluation
  """

  @enforce_keys [:ref, :tag]
  defstruct [:ref, :tag]

  @typedoc """
  A compiled quick scanner for a single tag name.

  The `:ref` field holds the NIF resource reference. The `:tag` field stores
  the tag name for inspection.
  """
  @type t :: %__MODULE__{ref: reference(), tag: String.t()}

  @doc """
  Creates a scanner for the given tag name.

  This is the only allocation. The scanner compiles the tag name into a
  SIMD-optimized byte pattern that can be reused across any number of
  documents.

  ## Examples

      iex> scanner = SimdXml.Quick.new("claim")
      iex> scanner.tag
      "claim"
  """
  @spec new(String.t()) :: t()
  def new(tag) when is_binary(tag) do
    ref = SimdXml.Native.quick_scanner_new(tag)
    %__MODULE__{ref: ref, tag: tag}
  end

  @doc """
  Extracts the text content of the first matching tag.

  Returns `nil` if the tag is not found, or if the matched element contains
  nested child elements (in which case, use the full parser instead).

  ## Examples

      iex> scanner = SimdXml.Quick.new("title")
      iex> SimdXml.Quick.extract_first(scanner, "<r><title>Hello</title></r>")
      "Hello"

      iex> scanner = SimdXml.Quick.new("missing")
      iex> SimdXml.Quick.extract_first(scanner, "<r><title>Hello</title></r>")
      nil
  """
  @spec extract_first(t(), binary()) :: String.t() | nil
  def extract_first(%__MODULE__{ref: ref}, data) when is_binary(data) do
    SimdXml.Native.quick_extract_first(ref, data)
  end

  @doc """
  Checks whether the tag exists anywhere in the document.

  Faster than `extract_first/2` when you only need a boolean answer, because
  it short-circuits after the first match without extracting text.

  ## Examples

      iex> scanner = SimdXml.Quick.new("title")
      iex> SimdXml.Quick.exists?(scanner, "<r><title>A</title></r>")
      true

      iex> scanner = SimdXml.Quick.new("missing")
      iex> SimdXml.Quick.exists?(scanner, "<r><title>A</title></r>")
      false
  """
  @spec exists?(t(), binary()) :: boolean()
  def exists?(%__MODULE__{ref: ref}, data) when is_binary(data) do
    SimdXml.Native.quick_exists(ref, data)
  end

  @doc """
  Counts occurrences of the tag (both open tags and self-closing tags).

  ## Examples

      iex> scanner = SimdXml.Quick.new("item")
      iex> SimdXml.Quick.count(scanner, "<r><item>A</item><item/></r>")
      2

      iex> scanner = SimdXml.Quick.new("missing")
      iex> SimdXml.Quick.count(scanner, "<r/>")
      0
  """
  @spec count(t(), binary()) :: non_neg_integer()
  def count(%__MODULE__{ref: ref}, data) when is_binary(data) do
    SimdXml.Native.quick_count(ref, data)
  end
end

defimpl Inspect, for: SimdXml.Quick do
  def inspect(%SimdXml.Quick{tag: tag}, _opts) do
    "#SimdXml.Quick<#{inspect(tag)}>"
  end
end

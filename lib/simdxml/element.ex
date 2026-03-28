defmodule SimdXml.Element do
  @moduledoc """
  A read-only XML element reference for navigating parsed documents.

  Elements are lightweight handles consisting of a document reference plus an
  integer index into the structural array. All data lives in Rust; accessor
  functions cross the NIF boundary on demand. Elements are valid as long as
  their parent `SimdXml.Document` is alive, which is guaranteed because each
  element holds the document reference.

  ## Navigation

  Elements provide tree navigation: `children/1`, `parent/1`, attribute access
  via `get/2` and `attributes/1`, and text extraction with `text/1` and
  `text_content/1`.

  ## Enumerable

  Elements implement `Enumerable` over their child elements, so standard `Enum`
  functions work directly:

      root = SimdXml.Document.root(doc)
      Enum.map(root, & &1.tag)
      #=> ["book", "book", "book"]

      Enum.count(root)
      #=> 3

  ## XPath from context

  You can evaluate XPath expressions with any element as the context node using
  `xpath_text/2`. This is useful for relative queries within a subtree.

  ## Examples

      iex> doc = SimdXml.parse!("<book lang='en'><title>Rust</title></book>")
      iex> root = SimdXml.Document.root(doc)
      iex> root.tag
      "book"
      iex> SimdXml.Element.get(root, "lang")
      "en"
      iex> SimdXml.Element.text(root)
      nil
      iex> [title] = Enum.to_list(root)
      iex> title.tag
      "title"
      iex> SimdXml.Element.text(title)
      "Rust"

  ## Related modules

    * `SimdXml.Document` - obtain the root element with `Document.root/1`
    * `SimdXml` - top-level XPath evaluation without element navigation
  """

  @enforce_keys [:doc_ref, :tag_idx, :tag]
  defstruct [:doc_ref, :tag_idx, :tag]

  @type t :: %__MODULE__{
          doc_ref: reference(),
          tag_idx: non_neg_integer(),
          tag: String.t()
        }

  @doc false
  def new(doc_ref, tag_idx) do
    tag = SimdXml.Native.element_tag(doc_ref, tag_idx)
    %__MODULE__{doc_ref: doc_ref, tag_idx: tag_idx, tag: tag}
  end

  @doc """
  Returns the direct child text content, or `nil` if the element has no text
  children.

  Only immediate text nodes are returned. For `<p>Hello <b>world</b></p>`,
  `text(p)` returns `"Hello "` because `"world"` is a child of `<b>`, not `<p>`.
  Use `text_content/1` to get all descendant text concatenated.

  ## Examples

      iex> doc = SimdXml.parse!("<r><a>hello</a></r>")
      iex> [a] = SimdXml.Element.children(SimdXml.Document.root(doc))
      iex> SimdXml.Element.text(a)
      "hello"

      iex> doc = SimdXml.parse!("<r><a><b>nested</b></a></r>")
      iex> [a] = SimdXml.Element.children(SimdXml.Document.root(doc))
      iex> SimdXml.Element.text(a)
      nil
  """
  @spec text(t()) :: String.t() | nil
  def text(%__MODULE__{doc_ref: ref, tag_idx: idx}) do
    SimdXml.Native.element_text(ref, idx)
  end

  @doc """
  Returns all descendant text concatenated into a single string.

  This is the XPath string-value of the element. For
  `<p>Hello <b>world</b></p>`, returns `"Hello world"`.

  ## Examples

      iex> doc = SimdXml.parse!("<p>Hello <b>world</b></p>")
      iex> root = SimdXml.Document.root(doc)
      iex> SimdXml.Element.text_content(root)
      "Hello world"
  """
  @spec text_content(t()) :: String.t()
  def text_content(%__MODULE__{doc_ref: ref, tag_idx: idx}) do
    SimdXml.Native.element_all_text(ref, idx)
  end

  @doc """
  Returns the attribute map for this element.

  Returns an empty map if the element has no attributes.

  ## Examples

      iex> doc = SimdXml.parse!("<book lang='en' year='2024'/>")
      iex> root = SimdXml.Document.root(doc)
      iex> SimdXml.Element.attributes(root)
      %{"lang" => "en", "year" => "2024"}

      iex> doc = SimdXml.parse!("<book/>")
      iex> root = SimdXml.Document.root(doc)
      iex> SimdXml.Element.attributes(root)
      %{}
  """
  @spec attributes(t()) :: %{String.t() => String.t()}
  def attributes(%__MODULE__{doc_ref: ref, tag_idx: idx}) do
    SimdXml.Native.element_attributes(ref, idx) |> Map.new()
  end

  @doc """
  Gets a single attribute value by name, or `nil` if not present.

  More efficient than `attributes/1` when you only need one attribute, because
  it avoids building the full map.

  ## Examples

      iex> doc = SimdXml.parse!("<book lang='en'/>")
      iex> root = SimdXml.Document.root(doc)
      iex> SimdXml.Element.get(root, "lang")
      "en"

      iex> doc = SimdXml.parse!("<book lang='en'/>")
      iex> root = SimdXml.Document.root(doc)
      iex> SimdXml.Element.get(root, "missing")
      nil
  """
  @spec get(t(), String.t()) :: String.t() | nil
  def get(%__MODULE__{doc_ref: ref, tag_idx: idx}, attr_name) do
    SimdXml.Native.element_get_attribute(ref, idx, attr_name)
  end

  @doc """
  Returns a list of direct child elements.

  Only element children are returned -- text nodes and comments are excluded.
  The returned elements are themselves navigable with all `SimdXml.Element`
  functions.

  You can also use `Enum` functions directly on an element, which iterates
  over children.

  ## Examples

      iex> doc = SimdXml.parse!("<r><a/><b/><c/></r>")
      iex> root = SimdXml.Document.root(doc)
      iex> children = SimdXml.Element.children(root)
      iex> Enum.map(children, & &1.tag)
      ["a", "b", "c"]
  """
  @spec children(t()) :: [t()]
  def children(%__MODULE__{doc_ref: ref, tag_idx: idx}) do
    SimdXml.Native.element_children(ref, idx)
    |> Enum.map(&new(ref, &1))
  end

  @doc """
  Returns the parent element, or `nil` for the root element.

  ## Examples

      iex> doc = SimdXml.parse!("<r><a/></r>")
      iex> root = SimdXml.Document.root(doc)
      iex> [child] = SimdXml.Element.children(root)
      iex> parent = SimdXml.Element.parent(child)
      iex> parent.tag
      "r"

      iex> doc = SimdXml.parse!("<r/>")
      iex> root = SimdXml.Document.root(doc)
      iex> SimdXml.Element.parent(root)
      nil
  """
  @spec parent(t()) :: t() | nil
  def parent(%__MODULE__{doc_ref: ref, tag_idx: idx}) do
    case SimdXml.Native.element_parent(ref, idx) do
      nil -> nil
      parent_idx -> new(ref, parent_idx)
    end
  end

  @doc """
  Returns the raw XML markup for this element and all its contents.

  Useful for extracting a subtree as a string, for example to pass to another
  parser or to store as a fragment.

  ## Examples

      iex> doc = SimdXml.parse!("<r><a><b>text</b></a></r>")
      iex> root = SimdXml.Document.root(doc)
      iex> [a] = SimdXml.Element.children(root)
      iex> SimdXml.Element.raw_xml(a)
      "<a><b>text</b></a>"
  """
  @spec raw_xml(t()) :: String.t()
  def raw_xml(%__MODULE__{doc_ref: ref, tag_idx: idx}) do
    SimdXml.Native.element_raw_xml(ref, idx)
  end

  @doc """
  Evaluates an XPath expression with this element as the context node.

  This allows relative XPath queries within a subtree. For example, you can
  find all `<b>` children of a specific `<a>` element without matching `<b>`
  elements elsewhere in the document.

  ## Examples

      iex> doc = SimdXml.parse!("<r><a><b>1</b></a><a><b>2</b></a></r>")
      iex> root = SimdXml.Document.root(doc)
      iex> [first | _] = SimdXml.Element.children(root)
      iex> SimdXml.Element.xpath_text(first, "./b")
      {:ok, ["1"]}
  """
  @spec xpath_text(t(), String.t()) :: {:ok, [String.t()]} | {:error, String.t()}
  def xpath_text(%__MODULE__{doc_ref: ref, tag_idx: idx}, expr) do
    SimdXml.Native.xpath_text_from(ref, expr, idx)
  end
end

defimpl Inspect, for: SimdXml.Element do
  def inspect(%SimdXml.Element{tag: tag, tag_idx: idx}, _opts) do
    "#SimdXml.Element<#{tag} @#{idx}>"
  end
end

defimpl Enumerable, for: SimdXml.Element do
  def count(%SimdXml.Element{doc_ref: ref, tag_idx: idx}) do
    {:ok, length(SimdXml.Native.element_children(ref, idx))}
  end

  def member?(_element, _value), do: {:error, __MODULE__}

  def reduce(%SimdXml.Element{doc_ref: ref, tag_idx: idx}, acc, fun) do
    SimdXml.Native.element_children(ref, idx)
    |> Enum.map(&SimdXml.Element.new(ref, &1))
    |> Enumerable.List.reduce(acc, fun)
  end

  def slice(_element), do: {:error, __MODULE__}
end

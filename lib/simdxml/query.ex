defmodule SimdXml.Query do
  @moduledoc """
  Composable XPath query builders for programmatic query construction.

  Build XPath queries using Elixir pipes instead of writing XPath strings by
  hand. Queries are plain data structures that compile to XPath at evaluation
  time via `to_xpath/1`. They are designed to be pipe-friendly, composable,
  and reusable.

  ## Why use Query instead of raw XPath?

    * **Type safety** - invalid axis/predicate combinations fail at build time
    * **Composability** - extract common fragments into variables and reuse them
    * **Readability** - Elixir pipes read more naturally than nested XPath

  ## Examples

      import SimdXml.Query

      # //book[@lang='en']/title/text()
      descendant("book") |> where_attr("lang", "en") |> child("title") |> text()

      # //section[count(./p) > 3]
      descendant("section") |> where_expr("count(./p) > 3")

      # //claim | //abstract
      union(descendant("claim"), descendant("abstract"))

      # Reusable fragments
      books = descendant("book")
      english = books |> where_attr("lang", "en")
      titles = english |> child("title") |> text()

  ## Execution

  Execute queries against parsed documents with `SimdXml.query/2`:

      doc = SimdXml.parse!(xml)
      SimdXml.query!(doc, titles)

  ## Return types

  By default, queries return `:text` (direct child text). Change the return
  type with these terminal functions:

    * `text/1` - append `/text()` step, return direct text (default)
    * `string/1` - return string-value (all descendant text concatenated)
    * `nodes/1` - return element node references
    * `count/1` - return match count
    * `exists/1` - return boolean

  ## Inspecting the generated XPath

  Use `to_xpath/1` to see what XPath string a query compiles to:

      iex> import SimdXml.Query
      iex> to_xpath(descendant("book") |> child("title"))
      "//book/title"

  ## Related modules

    * `SimdXml` - `query/2` and `query!/2` execute `Query` structs
    * `SimdXml.XPath` - compiled XPath for repeated evaluation
  """

  @enforce_keys [:steps]
  defstruct steps: [], return_type: :text

  @typedoc """
  A single step in the query pipeline.

  Steps are accumulated in a list and compiled to XPath by `to_xpath/1`.
  """
  @type step ::
          {:axis, atom(), String.t() | :any}
          | {:predicate, String.t()}
          | {:attr_predicate, String.t(), String.t()}
          | {:position, pos_integer()}
          | :text_step
          | {:union, [t()]}

  @typedoc """
  A composable query that compiles to XPath.

  The `:steps` list holds the accumulated axis steps, predicates, and modifiers.
  The `:return_type` determines how `SimdXml.query/2` evaluates the result.
  """
  @type t :: %__MODULE__{
          steps: [step()],
          return_type: :text | :string | :nodes | :count | :exists
        }

  # ---------------------------------------------------------------------------
  # Axis constructors (start a new query)
  # ---------------------------------------------------------------------------

  @doc """
  Starts a query matching elements anywhere in the document tree.

  Compiles to `//name` (the descendant-or-self shorthand). Pass `:any` or omit
  the argument to match all elements (`//*`).

  ## Examples

      iex> import SimdXml.Query
      iex> to_xpath(descendant("book"))
      "//book"

      iex> import SimdXml.Query
      iex> to_xpath(descendant())
      "//*"
  """
  @spec descendant(String.t() | :any) :: t()
  def descendant(name \\ :any) do
    %__MODULE__{steps: [{:axis, :descendant_or_self, :any}, {:axis, :child, name}]}
  end

  @doc """
  Starts a query matching direct children of the context node.

  Compiles to `child::name` or just `name` when used as a step. Pass `:any`
  or omit the argument to match all child elements.

  ## Examples

      iex> import SimdXml.Query
      iex> to_xpath(child("title"))
      "title"

      iex> import SimdXml.Query
      iex> to_xpath(child())
      "*"
  """
  @spec child(String.t() | :any) :: t()
  def child(name \\ :any) do
    %__MODULE__{steps: [{:axis, :child, name}]}
  end

  @doc """
  Starts a query matching the context node itself.

  Compiles to `self::name`. Rarely used as a starting point, but useful in
  predicate sub-expressions.

  ## Examples

      iex> import SimdXml.Query
      iex> to_xpath(self_node("book"))
      "self::book"
  """
  @spec self_node(String.t() | :any) :: t()
  def self_node(name \\ :any) do
    %__MODULE__{steps: [{:axis, :self, name}]}
  end

  @doc """
  Starts a query matching the parent element.

  Compiles to `parent::name`.

  ## Examples

      iex> import SimdXml.Query
      iex> to_xpath(parent("section"))
      "parent::section"
  """
  @spec parent(String.t() | :any) :: t()
  def parent(name \\ :any) do
    %__MODULE__{steps: [{:axis, :parent, name}]}
  end

  @doc """
  Starts a query matching ancestor elements.

  Compiles to `ancestor::name`.

  ## Examples

      iex> import SimdXml.Query
      iex> to_xpath(ancestor("document"))
      "ancestor::document"
  """
  @spec ancestor(String.t() | :any) :: t()
  def ancestor(name \\ :any) do
    %__MODULE__{steps: [{:axis, :ancestor, name}]}
  end

  @doc """
  Starts a query matching following sibling elements.

  Compiles to `following-sibling::name`.

  ## Examples

      iex> import SimdXml.Query
      iex> to_xpath(following_sibling("item"))
      "following-sibling::item"
  """
  @spec following_sibling(String.t() | :any) :: t()
  def following_sibling(name \\ :any) do
    %__MODULE__{steps: [{:axis, :following_sibling, name}]}
  end

  @doc """
  Starts a query matching preceding sibling elements.

  Compiles to `preceding-sibling::name`.

  ## Examples

      iex> import SimdXml.Query
      iex> to_xpath(preceding_sibling("item"))
      "preceding-sibling::item"
  """
  @spec preceding_sibling(String.t() | :any) :: t()
  def preceding_sibling(name \\ :any) do
    %__MODULE__{steps: [{:axis, :preceding_sibling, name}]}
  end

  @doc """
  Starts a query matching an attribute by name.

  Compiles to `attribute::name`.

  ## Examples

      iex> import SimdXml.Query
      iex> to_xpath(attribute("lang"))
      "attribute::lang"
  """
  @spec attribute(String.t()) :: t()
  def attribute(name) do
    %__MODULE__{steps: [{:axis, :attribute, name}]}
  end

  # ---------------------------------------------------------------------------
  # Pipe-based step appenders
  # ---------------------------------------------------------------------------

  @doc """
  Appends a child step to an existing query.

  Compiles to `/name` appended to the current path.

  ## Examples

      iex> import SimdXml.Query
      iex> to_xpath(descendant("book") |> child("title"))
      "//book/title"
  """
  @spec child(t(), String.t() | :any) :: t()
  def child(%__MODULE__{} = q, name) do
    %{q | steps: q.steps ++ [{:axis, :child, name}]}
  end

  @doc """
  Appends a descendant step to an existing query.

  Compiles to `//name` appended to the current path.

  ## Examples

      iex> import SimdXml.Query
      iex> to_xpath(child("section") |> descendant("p"))
      "section//p"
  """
  @spec descendant(t(), String.t() | :any) :: t()
  def descendant(%__MODULE__{} = q, name) do
    %{q | steps: q.steps ++ [{:axis, :descendant_or_self, :any}, {:axis, :child, name}]}
  end

  @doc """
  Appends a parent step to an existing query.

  Compiles to `/parent::name`.

  ## Examples

      iex> import SimdXml.Query
      iex> to_xpath(descendant("title") |> parent("book"))
      "//title/parent::book"
  """
  @spec parent(t(), String.t() | :any) :: t()
  def parent(%__MODULE__{} = q, name) do
    %{q | steps: q.steps ++ [{:axis, :parent, name}]}
  end

  @doc """
  Appends an ancestor step to an existing query.

  Compiles to `/ancestor::name`.

  ## Examples

      iex> import SimdXml.Query
      iex> to_xpath(descendant("title") |> ancestor("library"))
      "//title/ancestor::library"
  """
  @spec ancestor(t(), String.t() | :any) :: t()
  def ancestor(%__MODULE__{} = q, name) do
    %{q | steps: q.steps ++ [{:axis, :ancestor, name}]}
  end

  @doc """
  Appends a following-sibling step to an existing query.

  Compiles to `/following-sibling::name`.

  ## Examples

      iex> import SimdXml.Query
      iex> to_xpath(descendant("h1") |> following_sibling("p"))
      "//h1/following-sibling::p"
  """
  @spec following_sibling(t(), String.t() | :any) :: t()
  def following_sibling(%__MODULE__{} = q, name) do
    %{q | steps: q.steps ++ [{:axis, :following_sibling, name}]}
  end

  @doc """
  Appends a preceding-sibling step to an existing query.

  Compiles to `/preceding-sibling::name`.

  ## Examples

      iex> import SimdXml.Query
      iex> to_xpath(descendant("h2") |> preceding_sibling("h1"))
      "//h2/preceding-sibling::h1"
  """
  @spec preceding_sibling(t(), String.t() | :any) :: t()
  def preceding_sibling(%__MODULE__{} = q, name) do
    %{q | steps: q.steps ++ [{:axis, :preceding_sibling, name}]}
  end

  @doc """
  Appends an attribute step to an existing query.

  Compiles to `/attribute::name`.

  ## Examples

      iex> import SimdXml.Query
      iex> to_xpath(descendant("book") |> attribute("lang"))
      "//book/attribute::lang"
  """
  @spec attribute(t(), String.t()) :: t()
  def attribute(%__MODULE__{} = q, name) do
    %{q | steps: q.steps ++ [{:axis, :attribute, name}]}
  end

  # ---------------------------------------------------------------------------
  # Predicates
  # ---------------------------------------------------------------------------

  @doc """
  Filters by attribute value: `[@name='value']`.

  Appends a predicate that matches elements where the named attribute equals
  the given value. Single quotes in the value are escaped automatically.

  ## Examples

      iex> import SimdXml.Query
      iex> to_xpath(descendant("book") |> where_attr("lang", "en"))
      "//book[@lang='en']"
  """
  @spec where_attr(t(), String.t(), String.t()) :: t()
  def where_attr(%__MODULE__{} = q, attr_name, attr_value) do
    %{q | steps: q.steps ++ [{:attr_predicate, attr_name, attr_value}]}
  end

  @doc """
  Filters by attribute existence: `[@name]`.

  Appends a predicate that matches elements which have the named attribute,
  regardless of its value.

  ## Examples

      iex> import SimdXml.Query
      iex> to_xpath(descendant("book") |> has_attr("lang"))
      "//book[@lang]"
  """
  @spec has_attr(t(), String.t()) :: t()
  def has_attr(%__MODULE__{} = q, attr_name) do
    %{q | steps: q.steps ++ [{:predicate, "@#{attr_name}"}]}
  end

  @doc """
  Filters by an arbitrary XPath predicate expression.

  The expression is inserted verbatim inside `[...]`. Use this for predicates
  that `where_attr/3` and `has_attr/2` cannot express.

  ## Examples

      iex> import SimdXml.Query
      iex> to_xpath(descendant("section") |> where_expr("count(./p) > 3"))
      "//section[count(./p) > 3]"

      iex> import SimdXml.Query
      iex> to_xpath(descendant("item") |> where_expr("position() < 5"))
      "//item[position() < 5]"
  """
  @spec where_expr(t(), String.t()) :: t()
  def where_expr(%__MODULE__{} = q, expr) do
    %{q | steps: q.steps ++ [{:predicate, expr}]}
  end

  @doc """
  Selects a match by position: `[n]`.

  XPath positions are 1-based. `at(q, 1)` selects the first match,
  `at(q, 2)` the second, and so on.

  ## Examples

      iex> import SimdXml.Query
      iex> to_xpath(descendant("item") |> at(3))
      "//item[3]"
  """
  @spec at(t(), pos_integer()) :: t()
  def at(%__MODULE__{} = q, position) when is_integer(position) and position > 0 do
    %{q | steps: q.steps ++ [{:position, position}]}
  end

  @doc """
  Selects the first match: `[1]`.

  Shorthand for `at(q, 1)`.

  ## Examples

      iex> import SimdXml.Query
      iex> to_xpath(descendant("item") |> first())
      "//item[1]"
  """
  @spec first(t()) :: t()
  def first(%__MODULE__{} = q), do: at(q, 1)

  @doc """
  Selects the last match: `[last()]`.

  ## Examples

      iex> import SimdXml.Query
      iex> to_xpath(descendant("item") |> last())
      "//item[last()]"
  """
  @spec last(t()) :: t()
  def last(%__MODULE__{} = q), do: where_expr(q, "last()")

  # ---------------------------------------------------------------------------
  # Return type modifiers
  # ---------------------------------------------------------------------------

  @doc """
  Appends a `text()` step and sets the return type to `:text`.

  This is the most common terminal step. It compiles to `/text()` and tells
  `SimdXml.query/2` to return direct child text of each match.

  ## Examples

      iex> import SimdXml.Query
      iex> to_xpath(descendant("title") |> text())
      "//title/text()"
  """
  @spec text(t()) :: t()
  def text(%__MODULE__{} = q) do
    %{q | steps: q.steps ++ [:text_step], return_type: :text}
  end

  @doc """
  Sets the return type to `:string` (all descendant text, XPath string-value).

  Unlike `text/1`, this does not append a `/text()` step. Instead, it tells
  `SimdXml.query/2` to use `xpath_string/2` which concatenates all descendant
  text of each matched element.

  ## Examples

      iex> import SimdXml.Query
      iex> q = descendant("p") |> string()
      iex> q.return_type
      :string
      iex> to_xpath(q)
      "//p"
  """
  @spec string(t()) :: t()
  def string(%__MODULE__{} = q), do: %{q | return_type: :string}

  @doc """
  Sets the return type to `:nodes` (element references).

  Tells `SimdXml.query/2` to return node references instead of text. Useful
  when you need to navigate the matched elements further.

  ## Examples

      iex> import SimdXml.Query
      iex> q = descendant("book") |> nodes()
      iex> q.return_type
      :nodes
  """
  @spec nodes(t()) :: t()
  def nodes(%__MODULE__{} = q), do: %{q | return_type: :nodes}

  @doc """
  Sets the return type to `:count`.

  Tells `SimdXml.query/2` to return the number of matches as a scalar value.

  ## Examples

      iex> import SimdXml.Query
      iex> q = descendant("item") |> count()
      iex> q.return_type
      :count
  """
  @spec count(t()) :: t()
  def count(%__MODULE__{} = q), do: %{q | return_type: :count}

  @doc """
  Sets the return type to `:exists` (boolean).

  Tells `SimdXml.query/2` to return a boolean indicating whether any matches
  exist.

  ## Examples

      iex> import SimdXml.Query
      iex> q = descendant("item") |> exists()
      iex> q.return_type
      :exists
  """
  @spec exists(t()) :: t()
  def exists(%__MODULE__{} = q), do: %{q | return_type: :exists}

  # ---------------------------------------------------------------------------
  # Union
  # ---------------------------------------------------------------------------

  @doc """
  Combines two queries with XPath union (`|`).

  The union matches nodes selected by either query. Both queries must be
  `SimdXml.Query` structs.

  ## Examples

      iex> import SimdXml.Query
      iex> to_xpath(union(descendant("claim"), descendant("abstract")))
      "//claim | //abstract"
  """
  @spec union(t(), t()) :: t()
  def union(%__MODULE__{} = a, %__MODULE__{} = b) do
    %__MODULE__{steps: [{:union, [a, b]}]}
  end

  @doc """
  Combines multiple queries with XPath union (`|`).

  Accepts a list of two or more queries.

  ## Examples

      iex> import SimdXml.Query
      iex> queries = [descendant("a"), descendant("b"), descendant("c")]
      iex> to_xpath(union(queries))
      "//a | //b | //c"
  """
  @spec union([t()]) :: t()
  def union(queries) when is_list(queries) and length(queries) >= 2 do
    %__MODULE__{steps: [{:union, queries}]}
  end

  # ---------------------------------------------------------------------------
  # Compilation to XPath string
  # ---------------------------------------------------------------------------

  @doc """
  Compiles a query to its XPath string representation.

  This is called automatically by `SimdXml.query/2`, but you can also call it
  directly to inspect the generated XPath or to pass the string to
  `SimdXml.compile/1`.

  ## Examples

      iex> import SimdXml.Query
      iex> to_xpath(descendant("book") |> child("title") |> text())
      "//book/title/text()"

      iex> import SimdXml.Query
      iex> to_xpath(descendant("book") |> where_attr("lang", "en") |> child("title"))
      "//book[@lang='en']/title"

      iex> import SimdXml.Query
      iex> to_xpath(descendant("section") |> where_expr("count(./p) > 3"))
      "//section[count(./p) > 3]"
  """
  @spec to_xpath(t()) :: String.t()
  def to_xpath(%__MODULE__{steps: steps}) do
    compile_steps(steps, "")
  end

  defp compile_steps([], acc), do: acc

  # Special case: descendant-or-self::node()/child::name -> //name
  defp compile_steps(
         [{:axis, :descendant_or_self, :any}, {:axis, :child, name} | rest],
         acc
       ) do
    new_acc =
      if acc == "" do
        "//" <> to_string_name(name)
      else
        acc <> "//" <> to_string_name(name)
      end

    compile_steps(rest, new_acc)
  end

  defp compile_steps([step | rest], acc) do
    new_acc =
      case step do
        {:axis, :child, name} ->
          if acc == "" do
            to_string_name(name)
          else
            acc <> "/" <> to_string_name(name)
          end

        {:axis, axis, name} ->
          if acc == "" do
            axis_string(axis) <> "::" <> to_string_name(name)
          else
            acc <> "/" <> axis_string(axis) <> "::" <> to_string_name(name)
          end

        {:predicate, expr} ->
          acc <> "[" <> expr <> "]"

        {:attr_predicate, name, value} ->
          acc <> "[@" <> name <> "='" <> escape_xpath(value) <> "']"

        {:position, n} ->
          acc <> "[" <> Integer.to_string(n) <> "]"

        :text_step ->
          acc <> "/text()"

        {:union, queries} ->
          queries
          |> Enum.map(&to_xpath/1)
          |> Enum.join(" | ")
      end

    compile_steps(rest, new_acc)
  end

  defp to_string_name(:any), do: "*"
  defp to_string_name(name) when is_binary(name), do: name

  defp axis_string(:child), do: "child"
  defp axis_string(:descendant_or_self), do: "descendant-or-self"
  defp axis_string(:parent), do: "parent"
  defp axis_string(:ancestor), do: "ancestor"
  defp axis_string(:self), do: "self"
  defp axis_string(:following_sibling), do: "following-sibling"
  defp axis_string(:preceding_sibling), do: "preceding-sibling"
  defp axis_string(:attribute), do: "attribute"

  defp escape_xpath(value) do
    String.replace(value, "'", "\\'")
  end
end

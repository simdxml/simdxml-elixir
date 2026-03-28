defmodule SimdXml.Result do
  @moduledoc """
  Convenience functions for extracting single or multiple results from XPath
  queries.

  Provides `all/2`, `one/2`, `one!/2`, and `fetch/2` -- common access patterns
  inspired by Ecto's `Repo.all` / `Repo.one` and Meeseeks' result API. These
  wrap `SimdXml.xpath_text!/2` with ergonomic return values for the most common
  cases.

  Use this module when you know whether you expect zero, one, or many results
  and want a clean API without manual pattern matching on lists.

  ## Examples

      doc = SimdXml.parse!("<books><title>A</title><title>B</title></books>")

      SimdXml.Result.all(doc, "//title")
      #=> ["A", "B"]

      SimdXml.Result.one(doc, "//title")
      #=> "A"

      SimdXml.Result.fetch(doc, "//missing")
      #=> :error

  ## Related modules

    * `SimdXml` - `xpath_text!/2` which these functions wrap
    * `SimdXml.Query` - build queries programmatically before passing to `all/2`
  """

  @doc """
  Returns all matching text values as a list.

  Returns an empty list if no elements match the XPath expression. Raises
  `SimdXml.Error` if the XPath expression itself is invalid.

  ## Examples

      iex> doc = SimdXml.parse!("<r><a>1</a><a>2</a></r>")
      iex> SimdXml.Result.all(doc, "//a")
      ["1", "2"]

      iex> doc = SimdXml.parse!("<r><a>1</a></r>")
      iex> SimdXml.Result.all(doc, "//missing")
      []
  """
  @spec all(SimdXml.Document.t(), String.t()) :: [String.t()]
  def all(%SimdXml.Document{} = doc, xpath_str) do
    SimdXml.xpath_text!(doc, xpath_str)
  end

  @doc """
  Returns the first matching text value, or `nil` if there are no matches.

  When multiple elements match, only the first (in document order) is returned.
  Raises `SimdXml.Error` if the XPath expression itself is invalid.

  ## Examples

      iex> doc = SimdXml.parse!("<r><a>first</a><a>second</a></r>")
      iex> SimdXml.Result.one(doc, "//a")
      "first"

      iex> doc = SimdXml.parse!("<r/>")
      iex> SimdXml.Result.one(doc, "//missing")
      nil
  """
  @spec one(SimdXml.Document.t(), String.t()) :: String.t() | nil
  def one(%SimdXml.Document{} = doc, xpath_str) do
    case SimdXml.xpath_text!(doc, xpath_str) do
      [first | _] -> first
      [] -> nil
    end
  end

  @doc """
  Returns the first matching text value, or raises if there are no matches.

  Use this when the element is expected to exist and its absence is an error
  in your application logic.

  ## Examples

      iex> doc = SimdXml.parse!("<r><a>hello</a></r>")
      iex> SimdXml.Result.one!(doc, "//a")
      "hello"
  """
  @spec one!(SimdXml.Document.t(), String.t()) :: String.t()
  def one!(%SimdXml.Document{} = doc, xpath_str) do
    case one(doc, xpath_str) do
      nil -> raise SimdXml.Error, "no match for #{xpath_str}"
      val -> val
    end
  end

  @doc """
  Returns `{:ok, value}` for the first match, or `:error` if there are no
  matches.

  Follows the same convention as `Map.fetch/2` and `Access.fetch/2`. Useful
  in `with` chains and other pattern-matching contexts.

  ## Examples

      iex> doc = SimdXml.parse!("<r><a>hello</a></r>")
      iex> SimdXml.Result.fetch(doc, "//a")
      {:ok, "hello"}

      iex> doc = SimdXml.parse!("<r/>")
      iex> SimdXml.Result.fetch(doc, "//missing")
      :error
  """
  @spec fetch(SimdXml.Document.t(), String.t()) :: {:ok, String.t()} | :error
  def fetch(%SimdXml.Document{} = doc, xpath_str) do
    case one(doc, xpath_str) do
      nil -> :error
      val -> {:ok, val}
    end
  end
end

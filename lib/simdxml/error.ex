defmodule SimdXml.Error do
  @moduledoc """
  Exception raised by bang (`!`) variants of SimdXml functions.

  All functions in `SimdXml`, `SimdXml.Document`, and `SimdXml.Result` that end
  with `!` raise this exception when an operation fails. The most common causes
  are:

    * **Malformed XML** - `SimdXml.parse!/1` raises when the input is not
      well-formed XML (unclosed tags, invalid encoding, etc.)
    * **Invalid XPath** - `SimdXml.compile!/1` and `SimdXml.xpath_text!/2`
      raise when the XPath expression has syntax errors
    * **No match** - `SimdXml.Result.one!/2` raises when the XPath matches
      no elements

  The `:message` field contains a human-readable error string from the Rust
  parser or XPath engine.

  ## Handling errors

  Prefer the non-bang variants (`parse/1`, `xpath_text/2`, `compile/1`) when
  you expect errors and want to handle them gracefully:

      case SimdXml.parse(user_input) do
        {:ok, doc} -> process(doc)
        {:error, reason} -> Logger.warning("Bad XML: \#{reason}")
      end

  Use the bang variants when failure is unexpected and should crash the process:

      # In a supervised worker -- let it crash and restart
      doc = SimdXml.parse!(xml)

  ## Examples

      iex> try do
      ...>   SimdXml.parse!("<unclosed>")
      ...> rescue
      ...>   e in SimdXml.Error -> e.message
      ...> end |> is_binary()
      true
  """
  defexception [:message]

  @impl true
  def exception(msg) when is_binary(msg), do: %__MODULE__{message: msg}
end

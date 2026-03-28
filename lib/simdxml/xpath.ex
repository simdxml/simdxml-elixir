defmodule SimdXml.XPath do
  @moduledoc """
  A compiled XPath expression for efficient reuse across documents.

  Compiling an XPath expression parses the expression string once and produces
  a NIF resource that can be evaluated against any number of documents without
  re-parsing. This is the recommended approach when running the same query
  against many documents.

  ## Compile-once-run-many pattern

  The typical workflow is:

    1. Compile the expression once at startup or module attribute time
    2. Parse documents as they arrive
    3. Evaluate the compiled query against each document

  ```elixir
  # Compile once
  query = SimdXml.compile!("//claim/text()")

  # Evaluate many times
  for xml <- xml_documents do
    doc = SimdXml.parse!(xml)
    SimdXml.eval_text!(doc, query)
  end
  ```

  ## Process safety

  Compiled XPath expressions are backed by Rust NIF resources with
  reference-counting. They can be safely shared across processes -- for example,
  stored in a module attribute, an ETS table, or passed via message to a pool
  of workers. No copying occurs; all processes share the same underlying
  compiled expression.

  ```elixir
  # Store in ETS for global access
  :ets.insert(:queries, {:title_query, SimdXml.compile!("//title")})

  # Or in a module attribute (compiled at build time)
  defmodule MyApp.XmlProcessor do
    @title_query SimdXml.compile!("//title")

    def extract_titles(xml) do
      doc = SimdXml.parse!(xml)
      SimdXml.eval_text!(doc, @title_query)
    end
  end
  ```

  ## Batch processing

  Compiled queries pair naturally with `SimdXml.Batch` for processing many
  documents at once:

      query = SimdXml.compile!("//claim")
      SimdXml.Batch.eval_text_bloom(xml_binaries, query)

  ## Available evaluation functions

    * `SimdXml.eval_text/2` / `SimdXml.eval_text!/2` - extract text of matches
    * `SimdXml.eval_count/2` / `SimdXml.eval_count!/2` - count matches
    * `SimdXml.eval_exists?/2` - boolean existence check

  ## Examples

      iex> query = SimdXml.compile!("//title")
      iex> doc1 = SimdXml.parse!("<r><title>A</title></r>")
      iex> doc2 = SimdXml.parse!("<r><title>B</title></r>")
      iex> SimdXml.eval_text!(doc1, query)
      ["A"]
      iex> SimdXml.eval_text!(doc2, query)
      ["B"]

  ## Related modules

    * `SimdXml` - `compile/1` and `compile!/1` create `XPath` structs
    * `SimdXml.Batch` - batch evaluation with compiled queries
    * `SimdXml.Query` - build XPath programmatically, then compile
  """

  @enforce_keys [:ref, :expr]
  defstruct [:ref, :expr]

  @typedoc """
  A compiled XPath expression.

  The `:ref` field holds the NIF resource reference (opaque). The `:expr` field
  stores the original XPath string for inspection and debugging.
  """
  @type t :: %__MODULE__{ref: reference(), expr: String.t()}
end

defimpl Inspect, for: SimdXml.XPath do
  def inspect(%SimdXml.XPath{expr: expr}, _opts) do
    "#SimdXml.XPath<#{inspect(expr)}>"
  end
end

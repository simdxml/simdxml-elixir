defmodule SimdXml.Batch do
  @moduledoc """
  Batch processing of many XML documents with a single compiled query.

  Designed for workloads that process thousands to millions of small XML
  documents with the same XPath expression. Documents are parsed and evaluated
  in a single NIF call, avoiding per-document Erlang/Rust boundary overhead.

  ## Bloom filter prescanning

  `eval_text_bloom/2` adds a bloom filter prescan step: before parsing each
  document, it scans the raw bytes for tag names referenced in the XPath
  expression. Documents that cannot possibly contain those tags are skipped
  entirely -- no parsing, no indexing, no evaluation. For selective queries
  over large collections, this can be 10x or more faster than `eval_text/2`.

  ## Examples

      query = SimdXml.compile!("//claim")
      xmls = [
        "<patent><claim>First</claim></patent>",
        "<patent><abstract>No claims here</abstract></patent>",
        "<patent><claim>Third</claim></patent>"
      ]

      {:ok, results} = SimdXml.Batch.eval_text(xmls, query)
      #=> {:ok, [["First"], [], ["Third"]]}

      # With bloom filtering (faster when most documents don't match)
      {:ok, results} = SimdXml.Batch.eval_text_bloom(xmls, query)
      #=> {:ok, [["First"], [], ["Third"]]}

  ## When to use Batch vs per-document evaluation

    * **Use Batch** when you have many documents and a single query. The
      amortized NIF call overhead and bloom filtering make it significantly
      faster.
    * **Use per-document evaluation** when you need different queries per
      document, or when you need element navigation beyond text extraction.

  ## Related modules

    * `SimdXml.XPath` - compiled queries required by batch functions
    * `SimdXml` - `compile/1` and `compile!/1` to create queries
    * `SimdXml.Quick` - even faster for simple `//tagname` extraction
  """

  alias SimdXml.XPath

  @doc """
  Evaluates a compiled XPath against a list of XML binaries.

  Returns `{:ok, results}` where `results` is a list of string lists, one per
  input document, in the same order. Returns `{:error, reason}` if any document
  fails to parse.

  ## Examples

      iex> query = SimdXml.compile!("//title")
      iex> xmls = ["<r><title>A</title></r>", "<r><title>B</title></r>"]
      iex> SimdXml.Batch.eval_text(xmls, query)
      {:ok, [["A"], ["B"]]}

      iex> query = SimdXml.compile!("//missing")
      iex> SimdXml.Batch.eval_text(["<r/>"], query)
      {:ok, [[]]}
  """
  @spec eval_text([binary()], XPath.t()) :: {:ok, [[String.t()]]} | {:error, String.t()}
  def eval_text(documents, %XPath{ref: xpath_ref}) when is_list(documents) do
    SimdXml.Native.batch_xpath_text(documents, xpath_ref)
  end

  @doc """
  Evaluates with bloom filter prescanning for faster selective queries.

  Before parsing each document, scans raw bytes for tag names in the XPath
  expression. Documents that cannot contain those tags are skipped entirely.
  The results are identical to `eval_text/2` -- skipped documents return
  empty lists.

  This is most effective when the query is selective (few documents match)
  and documents are large enough that skipping the parse is a meaningful
  savings.

  ## Examples

      iex> query = SimdXml.compile!("//rare_tag")
      iex> xmls = ["<r><common/></r>", "<r><rare_tag>found</rare_tag></r>"]
      iex> SimdXml.Batch.eval_text_bloom(xmls, query)
      {:ok, [[], ["found"]]}
  """
  @spec eval_text_bloom([binary()], XPath.t()) :: {:ok, [[String.t()]]} | {:error, String.t()}
  def eval_text_bloom(documents, %XPath{ref: xpath_ref}) when is_list(documents) do
    SimdXml.Native.batch_xpath_text_bloom(documents, xpath_ref)
  end
end

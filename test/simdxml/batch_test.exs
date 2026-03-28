defmodule SimdXml.BatchTest do
  use ExUnit.Case, async: true

  @doc1 "<r><title>Doc One</title></r>"
  @doc2 "<r><title>Doc Two</title></r>"
  @doc3 "<r><other>No title</other></r>"

  @small_docs Enum.map(1..3, fn i -> "<r><title>Doc #{i}</title></r>" end)

  # ---------------------------------------------------------------------------
  # eval_text/2
  # ---------------------------------------------------------------------------

  describe "eval_text/2" do
    test "evaluates across multiple documents" do
      query = SimdXml.compile!("//title")
      {:ok, results} = SimdXml.Batch.eval_text([@doc1, @doc2, @doc3], query)
      assert length(results) == 3
      assert Enum.at(results, 0) == ["Doc One"]
      assert Enum.at(results, 1) == ["Doc Two"]
      assert Enum.at(results, 2) == []
    end

    test "single document batch" do
      query = SimdXml.compile!("//title")
      {:ok, results} = SimdXml.Batch.eval_text([@doc1], query)
      assert results == [["Doc One"]]
    end

    test "empty document list" do
      query = SimdXml.compile!("//title")
      {:ok, results} = SimdXml.Batch.eval_text([], query)
      assert results == []
    end

    test "all documents match" do
      query = SimdXml.compile!("//title")
      {:ok, results} = SimdXml.Batch.eval_text(@small_docs, query)
      assert length(results) == 3
      assert Enum.all?(results, fn r -> length(r) == 1 end)
    end

    test "no documents match" do
      query = SimdXml.compile!("//missing")
      {:ok, results} = SimdXml.Batch.eval_text(@small_docs, query)
      assert Enum.all?(results, fn r -> r == [] end)
    end

    test "large batch (150 documents)" do
      docs = Enum.map(1..150, fn i -> "<r><v>#{i}</v></r>" end)
      query = SimdXml.compile!("//v")
      {:ok, results} = SimdXml.Batch.eval_text(docs, query)
      assert length(results) == 150

      # Verify each doc returned its own value
      for {[text], i} <- Enum.with_index(results, 1) do
        assert text == Integer.to_string(i)
      end
    end

    test "documents with multiple matches per doc" do
      docs = [
        "<r><item>a</item><item>b</item></r>",
        "<r><item>c</item></r>",
        "<r><other/></r>"
      ]

      query = SimdXml.compile!("//item")
      {:ok, results} = SimdXml.Batch.eval_text(docs, query)
      assert Enum.at(results, 0) == ["a", "b"]
      assert Enum.at(results, 1) == ["c"]
      assert Enum.at(results, 2) == []
    end
  end

  # ---------------------------------------------------------------------------
  # eval_text_bloom/2
  # ---------------------------------------------------------------------------

  describe "eval_text_bloom/2" do
    test "bloom filter produces same results as eval_text" do
      query = SimdXml.compile!("//title")
      {:ok, results} = SimdXml.Batch.eval_text_bloom([@doc1, @doc2, @doc3], query)
      assert length(results) == 3
      assert Enum.at(results, 0) == ["Doc One"]
      assert Enum.at(results, 1) == ["Doc Two"]
      assert Enum.at(results, 2) == []
    end

    test "bloom with empty list" do
      query = SimdXml.compile!("//title")
      {:ok, results} = SimdXml.Batch.eval_text_bloom([], query)
      assert results == []
    end

    test "bloom single document" do
      query = SimdXml.compile!("//title")
      {:ok, results} = SimdXml.Batch.eval_text_bloom([@doc1], query)
      assert results == [["Doc One"]]
    end

    test "bloom skips non-matching documents efficiently" do
      # Create docs where most don't contain the target tag
      matching = ["<r><target>found</target></r>"]
      non_matching = Enum.map(1..100, fn i -> "<r><other>#{i}</other></r>" end)
      all_docs = non_matching ++ matching ++ non_matching

      query = SimdXml.compile!("//target")
      {:ok, results} = SimdXml.Batch.eval_text_bloom(all_docs, query)
      assert length(results) == 201

      # Only the middle document should match
      match_count = Enum.count(results, fn r -> r != [] end)
      assert match_count == 1
      assert Enum.at(results, 100) == ["found"]
    end

    test "bloom large batch" do
      docs = Enum.map(1..150, fn i -> "<r><v>#{i}</v></r>" end)
      query = SimdXml.compile!("//v")
      {:ok, bloom_results} = SimdXml.Batch.eval_text_bloom(docs, query)
      {:ok, plain_results} = SimdXml.Batch.eval_text(docs, query)

      # Bloom must return same results as plain eval
      assert bloom_results == plain_results
    end

    test "bloom with selective query on mixed documents" do
      docs = [
        "<patent><claim>Claim 1</claim></patent>",
        "<article><title>Title</title></article>",
        "<patent><claim>Claim 2</claim><claim>Claim 3</claim></patent>",
        "<note><body>text</body></note>"
      ]

      query = SimdXml.compile!("//claim")
      {:ok, results} = SimdXml.Batch.eval_text_bloom(docs, query)
      assert Enum.at(results, 0) == ["Claim 1"]
      assert Enum.at(results, 1) == []
      assert Enum.at(results, 2) == ["Claim 2", "Claim 3"]
      assert Enum.at(results, 3) == []
    end
  end

  # ---------------------------------------------------------------------------
  # Consistency between eval_text and eval_text_bloom
  # ---------------------------------------------------------------------------

  describe "consistency" do
    test "both functions return identical results" do
      docs = [
        @doc1,
        @doc2,
        @doc3,
        "<r><title>Four</title><title>Five</title></r>",
        "<r/>"
      ]

      query = SimdXml.compile!("//title")
      {:ok, plain} = SimdXml.Batch.eval_text(docs, query)
      {:ok, bloom} = SimdXml.Batch.eval_text_bloom(docs, query)
      assert plain == bloom
    end
  end
end

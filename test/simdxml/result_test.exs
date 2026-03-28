defmodule SimdXml.ResultTest do
  use ExUnit.Case, async: true

  @xml "<r><title>First</title><title>Second</title></r>"
  @single "<r><title>Only</title></r>"
  @empty "<r><other>no titles here</other></r>"

  setup do
    %{doc: SimdXml.parse!(@xml)}
  end

  # ---------------------------------------------------------------------------
  # all/2
  # ---------------------------------------------------------------------------

  describe "all/2" do
    test "returns all matches", %{doc: doc} do
      results = SimdXml.Result.all(doc, "//title")
      assert length(results) == 2
    end

    test "preserves document order", %{doc: doc} do
      results = SimdXml.Result.all(doc, "//title")
      assert results == ["First", "Second"]
    end

    test "returns empty list for no matches", %{doc: doc} do
      assert SimdXml.Result.all(doc, "//missing") == []
    end

    test "single match returns list of one" do
      doc = SimdXml.parse!(@single)
      assert SimdXml.Result.all(doc, "//title") == ["Only"]
    end

    test "many matches" do
      items = Enum.map(1..10, fn i -> "<v>#{i}</v>" end) |> Enum.join()
      doc = SimdXml.parse!("<r>" <> items <> "</r>")
      results = SimdXml.Result.all(doc, "//v")
      assert length(results) == 10
      assert List.first(results) == "1"
      assert List.last(results) == "10"
    end
  end

  # ---------------------------------------------------------------------------
  # one/2
  # ---------------------------------------------------------------------------

  describe "one/2" do
    test "returns first match", %{doc: doc} do
      assert SimdXml.Result.one(doc, "//title") == "First"
    end

    test "returns nil for no matches", %{doc: doc} do
      assert SimdXml.Result.one(doc, "//missing") == nil
    end

    test "returns first when multiple matches exist", %{doc: doc} do
      # Verifies it picks "First" not "Second"
      assert SimdXml.Result.one(doc, "//title") == "First"
    end

    test "returns only match for single result" do
      doc = SimdXml.parse!(@single)
      assert SimdXml.Result.one(doc, "//title") == "Only"
    end
  end

  # ---------------------------------------------------------------------------
  # one!/2
  # ---------------------------------------------------------------------------

  describe "one!/2" do
    test "returns first match", %{doc: doc} do
      assert SimdXml.Result.one!(doc, "//title") == "First"
    end

    test "raises for no matches", %{doc: doc} do
      assert_raise SimdXml.Error, fn ->
        SimdXml.Result.one!(doc, "//missing")
      end
    end

    test "error message includes xpath expression" do
      doc = SimdXml.parse!(@empty)

      error =
        assert_raise SimdXml.Error, fn ->
          SimdXml.Result.one!(doc, "//title")
        end

      assert error.message =~ "//title"
    end

    test "error message mentions no match" do
      doc = SimdXml.parse!(@empty)

      error =
        assert_raise SimdXml.Error, fn ->
          SimdXml.Result.one!(doc, "//gone")
        end

      assert error.message =~ "no match"
    end
  end

  # ---------------------------------------------------------------------------
  # fetch/2
  # ---------------------------------------------------------------------------

  describe "fetch/2" do
    test "returns {:ok, value} for match", %{doc: doc} do
      assert {:ok, "First"} = SimdXml.Result.fetch(doc, "//title")
    end

    test "returns :error for no match", %{doc: doc} do
      assert :error = SimdXml.Result.fetch(doc, "//missing")
    end

    test "returns first match when multiple exist", %{doc: doc} do
      assert {:ok, "First"} = SimdXml.Result.fetch(doc, "//title")
    end

    test "works with position predicate" do
      doc = SimdXml.parse!(@xml)
      assert {:ok, "Second"} = SimdXml.Result.fetch(doc, "//title[2]")
    end

    test "works with attribute predicate" do
      xml = ~s(<r><item type="a">one</item><item type="b">two</item></r>)
      doc = SimdXml.parse!(xml)
      assert {:ok, "two"} = SimdXml.Result.fetch(doc, "//item[@type='b']")
    end
  end
end

defmodule SimdXml.Native do
  @moduledoc """
  Low-level NIF bindings to the simdxml Rust crate.

  You should not use this module directly. Use the higher-level `SimdXml`,
  `SimdXml.Document`, `SimdXml.Element`, and `SimdXml.Query` modules instead.
  """

  version = Mix.Project.config()[:version]

  use RustlerPrecompiled,
    otp_app: :simdxml,
    crate: "simdxml_nif",
    base_url: "https://github.com/simdxml/simdxml-elixir/releases/download/v#{version}",
    version: version,
    force_build: System.get_env("SIMDXML_BUILD") in ["1", "true"],
    targets: ~w(
      aarch64-apple-darwin
      x86_64-apple-darwin
      x86_64-unknown-linux-gnu
      x86_64-unknown-linux-musl
      aarch64-unknown-linux-gnu
      aarch64-unknown-linux-musl
      x86_64-pc-windows-msvc
    )

  # Parsing
  def parse(_binary), do: :erlang.nif_error(:nif_not_loaded)
  def parse_for_xpath(_binary, _xpath), do: :erlang.nif_error(:nif_not_loaded)

  # Document info
  def document_root(_doc), do: :erlang.nif_error(:nif_not_loaded)
  def document_tag_count(_doc), do: :erlang.nif_error(:nif_not_loaded)

  # XPath queries
  def xpath_text(_doc, _expr), do: :erlang.nif_error(:nif_not_loaded)
  def xpath_string(_doc, _expr), do: :erlang.nif_error(:nif_not_loaded)
  def xpath_text_from(_doc, _expr, _context_idx), do: :erlang.nif_error(:nif_not_loaded)
  def xpath_nodes(_doc, _expr), do: :erlang.nif_error(:nif_not_loaded)
  def eval(_doc, _expr), do: :erlang.nif_error(:nif_not_loaded)

  # Compiled XPath
  def compile_xpath(_expr), do: :erlang.nif_error(:nif_not_loaded)
  def compiled_eval_text(_doc, _compiled), do: :erlang.nif_error(:nif_not_loaded)
  def compiled_eval_count(_doc, _compiled), do: :erlang.nif_error(:nif_not_loaded)
  def compiled_eval_exists(_doc, _compiled), do: :erlang.nif_error(:nif_not_loaded)

  # Element navigation
  def element_tag(_doc, _tag_idx), do: :erlang.nif_error(:nif_not_loaded)
  def element_text(_doc, _tag_idx), do: :erlang.nif_error(:nif_not_loaded)
  def element_all_text(_doc, _tag_idx), do: :erlang.nif_error(:nif_not_loaded)
  def element_attributes(_doc, _tag_idx), do: :erlang.nif_error(:nif_not_loaded)
  def element_get_attribute(_doc, _tag_idx, _name), do: :erlang.nif_error(:nif_not_loaded)
  def element_children(_doc, _tag_idx), do: :erlang.nif_error(:nif_not_loaded)
  def element_parent(_doc, _tag_idx), do: :erlang.nif_error(:nif_not_loaded)
  def element_raw_xml(_doc, _tag_idx), do: :erlang.nif_error(:nif_not_loaded)

  # Batch
  def batch_xpath_text(_docs, _compiled), do: :erlang.nif_error(:nif_not_loaded)
  def batch_xpath_text_bloom(_docs, _compiled), do: :erlang.nif_error(:nif_not_loaded)

  # Quick scanner
  def quick_scanner_new(_tag), do: :erlang.nif_error(:nif_not_loaded)
  def quick_extract_first(_scanner, _data), do: :erlang.nif_error(:nif_not_loaded)
  def quick_exists(_scanner, _data), do: :erlang.nif_error(:nif_not_loaded)
  def quick_count(_scanner, _data), do: :erlang.nif_error(:nif_not_loaded)
end

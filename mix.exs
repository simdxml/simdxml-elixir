defmodule SimdXml.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/simdxml/simdxml-elixir"

  def project do
    [
      app: :simdxml,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      name: "SimdXml",
      source_url: @source_url,
      description:
        "SIMD-accelerated XML parser with full XPath 1.0. " <>
          "Rustler NIF wrapping simdxml for blazing fast XML processing."
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:rustler, "~> 0.37.3", runtime: false},
      {:rustler_precompiled, "~> 0.9"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      files: [
        "lib",
        "native/simdxml_nif/.cargo",
        "native/simdxml_nif/src",
        "native/simdxml_nif/Cargo.toml",
        "checksum-*.exs",
        "mix.exs",
        "README.md",
        "LICENSE"
      ],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "SimdXml",
      extras: [
        "pages/getting-started.livemd",
        "pages/query-combinators.livemd",
        "pages/performance.livemd"
      ],
      groups_for_extras: [
        Guides: Path.wildcard("pages/*.livemd")
      ],
      groups_for_modules: [
        Core: [SimdXml, SimdXml.Document, SimdXml.Element],
        Querying: [SimdXml.Query, SimdXml.XPath, SimdXml.Result],
        "Batch & Quick": [SimdXml.Batch, SimdXml.Quick],
        "Low-Level": [SimdXml.Native]
      ]
    ]
  end
end

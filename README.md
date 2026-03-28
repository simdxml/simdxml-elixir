# SimdXml

SIMD-accelerated XML parsing with full XPath 1.0 support for Elixir.

SimdXml parses XML into a flat structural index (~16 bytes per tag) using SIMD
instructions, then evaluates XPath expressions against it using array operations.
No DOM tree, no atom creation from untrusted input, no XXE vulnerabilities.

Wraps the [simdxml](https://crates.io/crates/simdxml) Rust crate via
[Rustler](https://github.com/rusterlium/rustler) NIFs with precompiled binaries
for all major platforms.

## Installation

```elixir
def deps do
  [{:simdxml, "~> 0.1.0"}]
end
```

Precompiled NIF binaries are provided for macOS (Apple Silicon, Intel), Linux
(x86_64, aarch64, musl), and Windows. Set `SIMDXML_BUILD=1` to compile from
source if needed.

## Quick start

```elixir
# Parse
doc = SimdXml.parse!("<library><book lang='en'><title>Elixir</title></book></library>")

# Query with XPath
SimdXml.xpath_text!(doc, "//title")
#=> ["Elixir"]

# Navigate elements (Enumerable)
root = SimdXml.Document.root(doc)
Enum.map(root, & &1.tag)
#=> ["book"]

# Attributes
[book] = SimdXml.Element.children(root)
SimdXml.Element.get(book, "lang")
#=> "en"
```

## Query combinators

Build XPath queries with Elixir pipes instead of strings:

```elixir
import SimdXml.Query

query = descendant("book") |> where_attr("lang", "en") |> child("title") |> text()

SimdXml.query!(doc, query)
#=> ["Elixir"]

# Inspect the generated XPath
SimdXml.Query.to_xpath(query)
#=> "//book[@lang='en']/title/text()"
```

Queries are composable data structures — extract common fragments and reuse them:

```elixir
books = descendant("book")
english = books |> where_attr("lang", "en")
titles = english |> child("title") |> text()
authors = english |> child("author") |> text()
```

## Compiled queries

Compile once, evaluate against many documents:

```elixir
query = SimdXml.compile!("//title")

SimdXml.eval_text!(doc1, query)
SimdXml.eval_text!(doc2, query)

# Optimized short-circuit operations
SimdXml.eval_count!(doc, query)     #=> 1
SimdXml.eval_exists?(doc, query)    #=> {:ok, true}
```

Compiled queries are NIF resources — safe to share across processes, store in
ETS, or hold in module attributes.

## Batch processing

Process thousands of documents with bloom filter prescanning:

```elixir
query = SimdXml.compile!("//claim")
{:ok, results} = SimdXml.Batch.eval_text_bloom(xml_binaries, query)
```

Documents that cannot contain the target tags are skipped without parsing.

## Quick grep mode

For simple `//tagname` extraction at memory bandwidth — no structural index:

```elixir
scanner = SimdXml.Quick.new("claim")
SimdXml.Quick.extract_first(scanner, xml)    #=> "First claim text"
SimdXml.Quick.exists?(scanner, xml)          #=> true
SimdXml.Quick.count(scanner, xml)            #=> 42
```

## Result helpers

```elixir
SimdXml.Result.one(doc, "//title")           #=> "Elixir"
SimdXml.Result.fetch(doc, "//title")         #=> {:ok, "Elixir"}
SimdXml.Result.all(doc, "//title")           #=> ["Elixir"]
```

## Why SimdXml?

| | SimdXml | SweetXml | Saxy |
|---|---------|----------|------|
| **Parser** | SIMD Rust NIF | xmerl (Erlang) | Pure Elixir SAX |
| **XPath** | Full 1.0 | Full 1.0 (via xmerl) | None |
| **Memory** | ~16 bytes/tag | ~350 bytes/node | Streaming |
| **Atom safety** | Strings only | Creates atoms | Strings only |
| **XXE safe** | No DTD processing | Vulnerable by default | No DTD processing |
| **API** | Combinators + XPath | `~x` sigil | SAX handlers |
| **Batch** | Bloom-filtered | No | No |

## Documentation

Full API docs and interactive Livebook guides:

- [Getting Started](pages/getting-started.livemd)
- [Query Combinators](pages/query-combinators.livemd)
- [Performance Guide](pages/performance.livemd)

## License

MIT

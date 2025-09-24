# glaph_rdf

A serialization-agnostic RDF 1.2 data model for Gleam. The library provides
validated term types (IRIs, blank nodes, canonical BCP&nbsp;47 language tags),
set-like graph and dataset collections, and helpers for converting between
human-readable IRIs and `gleam/uri.Uri` values.

## Key features

- **RFC 3987 IRI validation** – reject malformed IRIs and percent-encode
  non-ASCII code points when converting to `gleam/uri.Uri`.
- **BCP 47 language tags** – parse and canonicalise tags so that scripts are
  title-cased, regions uppercased, and grandfathered tags preserved.
- **Triple and quad collections** – duplicate-safe graphs and datasets with
  convenience helpers for merging, replacing named graphs, or querying
  membership.
- **URI interoperability** – convert between IRIs, `NamedNode`s, and
  `gleam/uri.Uri` values, decoding percent-encoded Unicode only when needed.

## Installation

Add `glaph_rdf` to your Gleam project:

```sh
gleam add glaph_rdf
```

## Quick start

```gleam
import gleam/int
import gleam/io
import gleam/uri
import glaph_rdf

pub fn main() {
  // IRIs are validated against RFC 3987 and RDF 1.2 restrictions
  let assert Ok(subject) = glaph_rdf.named_node("https://example.org/alice")
  let assert Ok(predicate) = glaph_rdf.named_node("https://xmlns.com/foaf/0.1/name")
  let literal = glaph_rdf.simple_literal("Alice")
  let triple = glaph_rdf.triple(glaph_rdf.SubjectNamed(subject), predicate, glaph_rdf.ObjectLiteral(literal))

  // Work with graphs and datasets as duplicate-free collections
  let graph = glaph_rdf.new_graph()
    |> glaph_rdf.graph_add(triple)
  let triple_count = glaph_rdf.graph_size(graph)
  io.println("Triple count: " <> int.to_string(triple_count))

  let dataset = glaph_rdf.new_dataset()
    |> glaph_rdf.dataset_add_triple(triple)
  let quad_count = glaph_rdf.dataset_quad_count(dataset)
  io.println("Dataset quads: " <> int.to_string(quad_count))

  // Interoperate with gleam/uri.Uri values
  let assert Ok(parsed_uri) = glaph_rdf.named_node_to_uri(subject)
  let uri_text = uri.to_string(parsed_uri)
  io.println("URI form: " <> uri_text)
  let assert Ok(roundtrip) = glaph_rdf.uri_to_iri(parsed_uri)
  io.println("IRI form: " <> roundtrip)
}
```

## Working with language tags

`glaph_rdf.language_tag/1` normalises tags to canonical casing:

```gleam
let assert Ok(tag) = glaph_rdf.language_tag("zh-Hant-tw")
// tag == LanguageTag("zh-Hant-TW")
```

The returned value can be used with `glaph_rdf.language_literal/2` to attach
language metadata to literals.

## Contributing

```sh
gleam test  # Run the test suite
```

Issues and pull requests are welcome! If you spot gaps in RDF 1.2 coverage or
have ideas for higher-level APIs, please open a discussion.

## License


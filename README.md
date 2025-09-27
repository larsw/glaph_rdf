# glaph_rdf

A comprehensive RDF 1.2 library for Gleam with built-in Turtle and TriG serialization.
The library provides validated term types (IRIs, blank nodes, canonical BCP&nbsp;47 language tags),
set-like graph and dataset collections, and full-featured RDF serializers with parsing support.

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
- **Comprehensive RDF serialization** – full W3C Turtle and TriG serializers with
  parsing, intelligent prefix management, and support for all RDF 1.2 term types.

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

## RDF Serialization Support

### Turtle Serializer

The library includes a comprehensive **Turtle (Terse RDF Triple Language)** serializer that supports the full W3C Turtle specification:

```gleam
import glaph_rdf/serializers/turtle
import glaph_rdf/graph
import glaph_rdf/term
import glaph_rdf/statement
import gleam/dict

// Create some RDF data
let subject = term.unsafe_named_node("http://example.org/alice")
let predicate = term.unsafe_named_node("http://xmlns.com/foaf/0.1/name") 
let object = term.ObjectLiteral(term.simple_literal("Alice"))
let triple = statement.Triple(term.SubjectNamed(subject), predicate, object)

let my_graph = graph.new() |> graph.add(triple)

// Serialize with prefixes
let prefixes = dict.new()
  |> dict.insert("foaf", "http://xmlns.com/foaf/0.1/")
  |> dict.insert("ex", "http://example.org/")

let turtle_doc = turtle.TurtleDocument(
  base: Some("http://example.org/"),
  prefixes: prefixes,
  graph: my_graph
)

let turtle_text = turtle.serialize(turtle_doc)
// Output:
// @base <http://example.org/> .
// @prefix ex: <http://example.org/> .
// @prefix foaf: <http://xmlns.com/foaf/0.1/> .
// ex:alice foaf:name "Alice" .
```

**Turtle Features:**
- **Full W3C Turtle compliance** with lexical analysis and recursive descent parsing
- **Intelligent prefix management** - automatically uses prefixes when beneficial
- **All RDF 1.2 term types** - IRIs, blank nodes, literals (simple, language-tagged, typed)
- **Proper escaping** - handles strings, IRIs, and Unicode correctly
- **Base URI support** - relative IRI resolution and `@base` directives
- **RDF shortcuts** - uses `a` for `rdf:type`, supports collection syntax `( )`
- **Blank node labels** - preserves and generates valid blank node identifiers
- **Comprehensive error reporting** - detailed parse errors with position information

### TriG Serializer  

The **TriG (RDF Dataset Serialization)** serializer extends Turtle to support multiple named graphs within RDF datasets:

```gleam
import glaph_rdf/serializers/trig
import glaph_rdf/dataset
import glaph_rdf/graph
import glaph_rdf/term

// Create triples for different graphs
let alice_triple = statement.Triple(
  term.SubjectNamed(term.unsafe_named_node("http://example.org/alice")),
  term.unsafe_named_node("http://xmlns.com/foaf/0.1/name"),
  term.ObjectLiteral(term.simple_literal("Alice"))
)

let bob_triple = statement.Triple(
  term.SubjectNamed(term.unsafe_named_node("http://example.org/bob")),
  term.unsafe_named_node("http://xmlns.com/foaf/0.1/name"), 
  term.ObjectLiteral(term.simple_literal("Bob"))
)

// Create named graphs
let people_graph = graph.new() |> graph.add(alice_triple)
let friends_graph = graph.new() |> graph.add(bob_triple)

// Build dataset with named graphs
let my_dataset = dataset.new()
  |> dataset.replace_graph(
       term.NamedGraph(term.unsafe_named_node("http://example.org/people")), 
       people_graph)
  |> dataset.replace_graph(
       term.NamedGraph(term.unsafe_named_node("http://example.org/friends")), 
       friends_graph)

let trig_doc = trig.TrigDocument(
  base: None,
  prefixes: dict.new(),
  dataset: my_dataset
)

let trig_text = trig.serialize(trig_doc)
// Output:
// <http://example.org/people> {
//     <http://example.org/alice> <http://xmlns.com/foaf/0.1/name> "Alice" .
// }
// <http://example.org/friends> {
//     <http://example.org/bob> <http://xmlns.com/foaf/0.1/name> "Bob" .  
// }
```

**TriG Features:**
- **Named graph serialization** - `<graph-name> { ... }` syntax for organizing triples
- **Blank node graphs** - supports `_:identifier { ... }` for anonymous graph names
- **Default graph handling** - triples without explicit graph context
- **Full Turtle compatibility** - inherits all Turtle features (prefixes, base URIs, shortcuts)
- **Mixed datasets** - seamlessly handles both default and named graph content
- **Turtle fallback parsing** - can parse regular Turtle documents as TriG

### Parsing Support

Both serializers provide robust parsing capabilities:

```gleam
// Parse Turtle
case turtle.parse(turtle_text) {
  Ok(document) -> {
    // Access parsed base, prefixes, and graph
    let graph_size = graph.size(document.graph)
  }
  Error(turtle.TurtleError(message, position)) -> {
    // Handle parse error with detailed information
  }
}

// Parse TriG (including Turtle compatibility)
case trig.parse(trig_text) {
  Ok(document) -> {
    // Access parsed dataset with multiple graphs
    let default_graph = dataset.default_graph(document.dataset) 
    let graph_names = dataset.graph_names(document.dataset)
  }
  Error(trig.TrigError(message, position)) -> {
    // Handle parse error
  }
}
```

### Testing Coverage

Both serializers include comprehensive test suites:
- **Turtle**: 50+ tests covering parsing, serialization, prefixes, literals, error handling
- **TriG**: 23+ tests covering named graphs, datasets, mixed content, escaping
- **Total**: 72+ tests ensuring robust RDF serialization support

## Contributing

```sh
gleam test  # Run the test suite
```

Issues and pull requests are welcome! If you spot gaps in RDF 1.2 coverage or
have ideas for higher-level APIs, please open a discussion.

## License


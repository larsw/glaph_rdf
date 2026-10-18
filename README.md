# glaph_rdf

A comprehensive RDF 1.2 library for Gleam with built-in Turtle, TriG, N-Triples and N-Quads serialization.
The library provides validated term types (IRIs, blank nodes, canonical BCP&nbsp;47 language tags),
set-like graph and dataset collections, and full-featured RDF serializers with parsing support.

## What is 'glaph'?

Gleam <3 Graph

## Key features

- **RFC 3987 IRI validation** – reject malformed IRIs and percent-encode
  non-ASCII code points when converting to `gleam/uri.Uri`.
- **BCP 47 language tags** – parse and canonicalise tags so that scripts are
  title-cased, regions uppercased, and grandfathered tags preserved.
- **Triple and quad collections** – duplicate-safe graphs and datasets with
  convenience helpers for merging, replacing named graphs, or querying
  membership.
- **RDF Graph and Dataset Isomorphism** – check semantic equivalence between
  graphs and datasets using canonical blank node labeling, enabling reliable
  comparison regardless of serialization order or blank node naming.
- **URI interoperability** – convert between IRIs, `NamedNode`s, and
  `gleam/uri.Uri` values, decoding percent-encoded Unicode only when needed.
- **RDF serialization** – Turtle, TriG, N-Triples and N-Quads writers and
  parsers with intelligent prefix management and support for all RDF 1.2 term
  types. The Turtle and TriG parsers cover the core grammar; see the Turtle
  section below for the syntax they do not read yet.

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

RDF 1.2 directional language-tagged strings (datatype `rdf:dirLangString`)
add a base direction, `ltr` or `rtl`:

```gleam
let assert Ok(tag) = glaph_rdf.language_tag("ar")
let assert Ok(direction) = glaph_rdf.base_direction("rtl")
let literal = glaph_rdf.directional_language_literal("مرحبا", tag, direction)
// N-Triples / N-Quads / Turtle / TriG: "مرحبا"@ar--rtl
```

N-Triples, N-Quads, Turtle and TriG all read and write the `@tag--ltr` /
`@tag--rtl` form. The language tag is case-insensitive, but the direction
must be exactly `ltr` or `rtl` in lowercase, as RDF 1.2 requires: `@en--LTR`
or `@en--up` is a parse error. A literal written with the datatype
`rdf:langString` or `rdf:dirLangString` (`"x"^^rdf:dirLangString`) is also a
parse error, because such literals must carry a language tag. `typed_literal`
does not check for these two datatypes, so a literal built that way is written
out as-is and cannot be read back; use `language_literal` or
`directional_language_literal` instead.

## RDF Serialization Support

### Turtle Serializer

The library includes a comprehensive **Turtle (Terse RDF Triple Language)** serializer and parser. The writer can express every RDF 1.2 graph built from
validated terms (numbers and booleans are written bare only when that form reads
back as the same literal; anything else is quoted with `^^`); the parser reads the
core Turtle grammar (see the limits listed below):

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
- **Recursive descent parser** for directives, predicate and object lists, all
  four string forms (`"…"`, `'…'`, `"""…"""`, `'''…'''`), numbers and booleans
- **Intelligent prefix management** - automatically uses prefixes when beneficial;
  `@prefix` lines are written sorted by label, so output is the same on Erlang
  and JavaScript
- **All RDF 1.2 term types** - IRIs, blank nodes, literals (simple,
  language-tagged, directional `"x"@en--ltr`, typed) and triple terms
  `<<( s p o )>>`
- **Proper escaping** - handles strings, IRIs, and Unicode correctly
- **Base URI support** - relative IRI resolution and `@base` directives
- **RDF shortcuts** - uses `a` for `rdf:type`
- **Blank node labels** - preserves and generates valid blank node identifiers
- **Comprehensive error reporting** - detailed parse errors with position information
- **Not yet supported when parsing**: collections `( … )`, `[ … ]` blank nodes,
  reified triples `<< … >>`, reifiers `s p o ~ r`, annotations `{| … |}`, the
  RDF 1.2 version directive (`VERSION "1.2"` / `@version "1.2" .`) and
  SPARQL-style `PREFIX` / `BASE`

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
- **Graph block parsing** - reads `{ … }`, `label { … }` and `GRAPH label { … }`
  blocks, and plain Turtle documents as the default graph

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

### File I/O Support

All serializers now support direct file operations in addition to string-based processing:

```gleam
import glaph_rdf/serializers/turtle

// Read RDF from file
case turtle.parse_graph_file("data/ontology.ttl") {
  Ok(graph) -> {
    let triple_count = graph.size(graph)
    // Process RDF graph
  }
  Error(error) -> // Handle file or parsing error
}

// Write RDF to file
let prefixes = dict.from_list([#("ex", "http://example.org/")])
case turtle.serialize_graph_to_file(my_graph, None, prefixes, "output/data.ttl") {
  Ok(Nil) -> // File written successfully
  Error(error) -> // Handle file write error
}
```

**File I/O Features:**
- **Cross-platform**: Uses `simplifile` for reliable file operations on all targets
- **Comprehensive error handling**: Detailed error messages with file paths and positions  
- **All formats supported**: Turtle, TriG, N-Triples, and N-Quads include file I/O functions
- **Streaming for N-Triples/N-Quads**: `streaming_parse_file` and `streaming_serialize_to_file` read and write line by line on both targets; `streaming_fold_file` processes a file in constant memory
- **Round-trip tested**: Full test coverage including error conditions and cross-format compatibility

**Available Functions:**
- `parse_file()` / `parse_graph_file()` / `parse_dataset_file()` - Read from files
- `serialize_to_file()` / `serialize_graph_to_file()` / `serialize_dataset_to_file()` - Write to files
- `streaming_parse_file()` / `streaming_fold_file()` / `streaming_serialize_to_file()` - Line-by-line file I/O (N-Triples and N-Quads)

For detailed documentation and examples, see [FILE_IO.md](docs/FILE_IO.md) and, for streaming, [STREAMING.md](docs/STREAMING.md).

### Testing Coverage

All serializers include comprehensive test suites:
- **Turtle**: 50+ tests covering parsing, serialization, prefixes, literals, error handling
- **TriG**: 23+ tests covering named graphs, datasets, mixed content, escaping  
- **N-Triples/N-Quads**: 25+ tests covering line-based parsing and dataset serialization
- **File I/O**: 15+ tests covering file operations, error handling, and round-trip validation
- **Total**: 115+ tests ensuring robust RDF serialization and file handling

## RDF Isomorphism and Semantic Comparison

The library provides powerful **RDF graph and dataset isomorphism** functionality for determining semantic equivalence between RDF structures. This is essential for comparing RDF data from different sources that may use different blank node labels but represent the same information.

### Graph Isomorphism

```gleam
import glaph_rdf/graph
import glaph_rdf/term
import glaph_rdf/statement

// Two graphs with different blank node labels but same structure
let graph1 = graph.from_list([
  statement.Triple(
    subject: term.SubjectBlank(term.unsafe_blank_node("person1")),
    predicate: term.unsafe_named_node("http://xmlns.com/foaf/0.1/name"),
    object: term.ObjectLiteral(term.simple_literal("Alice"))
  )
])

let graph2 = graph.from_list([
  statement.Triple(
    subject: term.SubjectBlank(term.unsafe_blank_node("x")),
    predicate: term.unsafe_named_node("http://xmlns.com/foaf/0.1/name"),
    object: term.ObjectLiteral(term.simple_literal("Alice"))
  )
])

// Check if graphs are semantically equivalent
graph.isomorphic(graph1, graph2)  // -> True

// Create canonical representation for comparison
let canonical1 = graph.canonicalize(graph1)
let canonical2 = graph.canonicalize(graph2)
// Both will have the same canonical blank node labels
```

### Dataset Isomorphism

```gleam
import glaph_rdf/dataset

// Compare entire datasets across multiple graphs
let dataset1 = dataset.from_list([
  statement.Quad(
    subject: term.SubjectBlank(term.unsafe_blank_node("a")),
    predicate: term.unsafe_named_node("http://xmlns.com/foaf/0.1/name"),
    object: term.ObjectLiteral(term.simple_literal("Alice")),
    graph: term.DefaultGraph
  ),
  statement.Quad(
    subject: term.SubjectBlank(term.unsafe_blank_node("b")),  
    predicate: term.unsafe_named_node("http://xmlns.com/foaf/0.1/name"),
    object: term.ObjectLiteral(term.simple_literal("Bob")),
    graph: term.NamedGraph(term.unsafe_named_node("http://example.org/people"))
  )
])

let dataset2 = dataset.from_list([/* same data with different blank node labels */])

dataset.isomorphic(dataset1, dataset2)  // -> True
```

**Isomorphism Features:**
- **Canonical Blank Node Labeling** – deterministic relabeling based on structural signatures
- **Multi-graph Support** – handles complex datasets with multiple named graphs
- **Blank Graph Names** – properly canonicalizes datasets with blank node graph identifiers  
- **Performance Optimized** – early size filtering and efficient comparison algorithms
- **Comprehensive Coverage** – handles all RDF term types including complex literal structures

**Use Cases:**
- **Data Integration** – verify that data from different sources represents the same information
- **Round-trip Testing** – ensure serialization/parsing preserves semantic meaning
- **Test Assertions** – compare expected vs actual results regardless of blank node naming
- **Data Deduplication** – identify semantically identical RDF structures

For detailed documentation and examples, see [ISOMORPHISM.md](docs/ISOMORPHISM.md).

## Contributing

```sh
gleam test  # Run the test suite
```

Issues and pull requests are welcome! If you spot gaps in RDF 1.2 coverage or
have ideas for higher-level APIs, please open a discussion.

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

Copyright 2025 Lars Wilhelmsen &lt;lars@sral.org&gt;


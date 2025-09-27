# TriG Serializer

This module provides TriG (RDF Dataset Serialization) support for the glaph_rdf library.

## Features

The TriG serializer extends Turtle functionality to support RDF datasets with named graphs:

### Supported TriG Features

- **Named Graphs**: Serialize RDF data grouped into named graphs using `<graph-name> { ... }` syntax
- **Blank Graph Names**: Support for blank node graph identifiers using `_:identifier { ... }` syntax  
- **Default Graph**: Triples without explicit graph context are placed in the default graph
- **Base URIs**: Support for `@base` directives
- **Prefixes**: Full support for `@prefix` declarations with intelligent prefix usage
- **All RDF Terms**: Named nodes, blank nodes, literals (simple, language-tagged, typed)
- **Escape Sequences**: Proper escaping of strings and IRIs
- **RDF Type Shorthand**: Uses `a` for `rdf:type` predicates

### Current Limitations

- **Parser**: Basic TriG parsing (falls back to Turtle parser for most cases)
- **Empty Named Graphs**: Empty graphs are not serialized (no quads means no graph tracking)
- **SPARQL Extensions**: Advanced TriG features like reified triples not yet supported

## API

### Core Functions

```gleam
// Parse TriG document
parse(text: String) -> Result(TrigDocument, TrigError)

// Parse to dataset directly  
parse_dataset(text: String) -> Result(dataset.Dataset, TrigError)

// Serialize complete document
serialize(document: TrigDocument) -> String

// Serialize dataset with base/prefixes
serialize_dataset(
  dataset: dataset.Dataset, 
  base: Option(String),
  prefixes: dict.Dict(String, String)
) -> String
```

### Types

```gleam
pub type TrigDocument {
  TrigDocument(
    base: Option(String),
    prefixes: dict.Dict(String, String), 
    dataset: dataset.Dataset,
  )
}

pub type TrigError {
  TrigError(message: String, position: Int)
}
```

## Usage Examples

### Basic Named Graph Serialization

```gleam
import glaph_rdf/serializers/trig
import glaph_rdf/dataset
import glaph_rdf/graph  
import glaph_rdf/statement
import glaph_rdf/term

// Create a triple
let triple = statement.Triple(
  term.SubjectNamed(term.unsafe_named_node("http://example.org/alice")),
  term.unsafe_named_node("http://xmlns.com/foaf/0.1/name"),
  term.ObjectLiteral(term.simple_literal("Alice"))
)

// Add to named graph
let graph_name = term.NamedGraph(term.unsafe_named_node("http://example.org/people"))
let my_dataset = 
  dataset.new()
  |> dataset.replace_graph(graph_name, 
       graph.new() |> graph.add(triple))

// Serialize
let doc = trig.TrigDocument(
  base: None,
  prefixes: dict.new(),
  dataset: my_dataset
)

trig.serialize(doc)
// Output: <http://example.org/people> {
//     <http://example.org/alice> <http://xmlns.com/foaf/0.1/name> "Alice" .
// }
```

### With Prefixes and Base

```gleam
let prefixes = 
  dict.new()
  |> dict.insert("ex", "http://example.org/")
  |> dict.insert("foaf", "http://xmlns.com/foaf/0.1/")

let doc = trig.TrigDocument(
  base: Some("http://example.org/base/"),
  prefixes: prefixes,
  dataset: my_dataset
)

trig.serialize(doc)
// Output: @base <http://example.org/base/> .
//         @prefix ex: <http://example.org/> .  
//         @prefix foaf: <http://xmlns.com/foaf/0.1/> .
//         ex:people {
//             ex:alice foaf:name "Alice" .
//         }
```

## Relationship to Turtle

The TriG serializer reuses the Turtle serializer for:
- Parsing basic Turtle syntax
- Prefix management and application
- Term serialization (literals, IRIs, blank nodes)
- String and IRI escaping

TriG extends this with dataset-level functionality for multiple named graphs.

## Testing

The module includes comprehensive tests covering:
- Empty documents and datasets
- Named graphs (IRI and blank node names)
- Default graph handling  
- Mixed default + named graph datasets
- Prefix usage and base URIs
- All literal types and escaping
- Round-trip parsing from Turtle to TriG
- Error handling

Run tests with: `gleam test`
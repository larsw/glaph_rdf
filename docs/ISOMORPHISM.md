# RDF Graph and Dataset Isomorphism

This document provides comprehensive documentation for the RDF graph and dataset isomorphism functionality in glaph_rdf.

## Overview

RDF isomorphism is crucial for determining when two RDF graphs or datasets are logically equivalent despite using different blank node labels. Two RDF structures are isomorphic if there exists a bijection between their blank nodes that makes them identical when applied.

## Graph Isomorphism

### API

#### `graph.isomorphic(graph1: Graph, graph2: Graph) -> Bool`

Determines if two RDF graphs are isomorphic (logically equivalent).

**Parameters:**
- `graph1`: First graph to compare
- `graph2`: Second graph to compare

**Returns:** `True` if graphs are isomorphic, `False` otherwise

**Examples:**
```gleam
import glaph_rdf/graph
import glaph_rdf/statement
import glaph_rdf/term

// Create two graphs with different blank node labels but same structure
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

graph.isomorphic(graph1, graph2)  // -> True
```

#### `graph.canonicalize(graph: Graph) -> Graph`

Creates a canonical representation of an RDF graph with normalized blank node labels.

**Parameters:**
- `graph`: Graph to canonicalize

**Returns:** Graph with canonical blank node labels

**Examples:**
```gleam
let original = graph.from_list([triples_with_blank_nodes])
let canonical = graph.canonicalize(original)
// All blank nodes now have deterministic labels like "b0", "b1", etc.
```

### Algorithm Details

The isomorphism algorithm uses canonical labeling with these steps:

1. **Blank Node Extraction**: Identify all blank nodes in both graphs
2. **Signature Calculation**: Create structural signatures for each blank node based on:
   - Connected predicates and objects
   - Relationship patterns with other nodes
   - Position in triples (subject vs object)
3. **Deterministic Labeling**: Sort blank nodes by signature and assign canonical labels
4. **Graph Comparison**: Compare canonicalized graphs for exact equality

### Complexity

- **Time Complexity**: O(n²) where n is the number of triples
- **Space Complexity**: O(n) for canonical representation
- **Worst Case**: Complex interconnected blank node structures

### Limitations

- Does not handle RDF-star quoted triples in blank node signatures (placeholder implementation)
- May be slow for very large graphs with many interconnected blank nodes
- Signature-based approach may not distinguish all possible blank node patterns

## Dataset Isomorphism

### API

#### `dataset.isomorphic(dataset1: Dataset, dataset2: Dataset) -> Bool`

Determines if two RDF datasets are isomorphic across all their graphs.

**Parameters:**
- `dataset1`: First dataset to compare
- `dataset2`: Second dataset to compare

**Returns:** `True` if datasets are isomorphic, `False` otherwise

**Examples:**
```gleam
import glaph_rdf/dataset
import glaph_rdf/statement
import glaph_rdf/term

// Create datasets with blank nodes in different graphs
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

let dataset2 = dataset.from_list([
  statement.Quad(
    subject: term.SubjectBlank(term.unsafe_blank_node("person1")),
    predicate: term.unsafe_named_node("http://xmlns.com/foaf/0.1/name"),
    object: term.ObjectLiteral(term.simple_literal("Alice")),
    graph: term.DefaultGraph
  ),
  statement.Quad(
    subject: term.SubjectBlank(term.unsafe_blank_node("person2")),
    predicate: term.unsafe_named_node("http://xmlns.com/foaf/0.1/name"),
    object: term.ObjectLiteral(term.simple_literal("Bob")),
    graph: term.NamedGraph(term.unsafe_named_node("http://example.org/people"))
  )
])

dataset.isomorphic(dataset1, dataset2)  // -> True
```

#### `dataset.canonicalize(dataset: Dataset) -> Dataset`

Creates a canonical representation of an RDF dataset with normalized blank node labels across all graphs.

**Parameters:**
- `dataset`: Dataset to canonicalize

**Returns:** Dataset with canonical blank node labels

**Examples:**
```gleam
let original = dataset.from_list([quads_with_blank_nodes])
let canonical = dataset.canonicalize(original)
// All blank nodes across all graphs now have deterministic labels
```

### Algorithm Details

Dataset isomorphism extends graph isomorphism to handle:

1. **Default Graph Comparison**: Check isomorphism of default graphs
2. **Named Graph Enumeration**: Identify and compare all named graphs
3. **Blank Graph Name Handling**: Canonicalize blank node graph names
4. **Per-Graph Isomorphism**: Apply graph isomorphism to each corresponding graph pair
5. **Structural Validation**: Ensure graph name correspondence is maintained

### Complexity

- **Time Complexity**: O(g × n²) where g is number of graphs, n is average graph size
- **Space Complexity**: O(g × n) for canonical representations
- **Graph Count Impact**: Linear scaling with number of named graphs

### Special Cases

- **Blank Graph Names**: Handled through canonical labeling of graph identifiers
- **Mixed Graph Types**: Named graphs and blank graphs compared appropriately
- **Empty Graphs**: Empty graphs in datasets are considered equivalent
- **Graph Name Mismatches**: Different graph name sets result in non-isomorphism

## Use Cases

### Data Integration
```gleam
// Check if data from different sources represents the same information
let source1_data = parse_turtle(source1_content)
let source2_data = parse_turtle(source2_content)

case graph.isomorphic(source1_data.graph, source2_data.graph) {
  True -> // Same information, can merge safely
  False -> // Different information, requires conflict resolution
}
```

### Data Validation
```gleam
// Verify round-trip serialization preserves semantics
let original = my_graph
let serialized = turtle.serialize(turtle.TurtleDocument(None, dict.new(), original))
let reparsed = turtle.parse(serialized).graph

graph.isomorphic(original, reparsed) |> should.be_true()
```

### Test Assertions
```gleam
// Assert semantic equivalence in tests regardless of serialization order
let expected_graph = construct_expected_graph()
let actual_graph = function_under_test()

graph.isomorphic(expected_graph, actual_graph) |> should.be_true()
```

### Dataset Comparison
```gleam
// Compare multi-graph datasets from different sources
let dataset1 = trig.parse(content1).dataset
let dataset2 = trig.parse(content2).dataset

dataset.isomorphic(dataset1, dataset2) |> should.be_true()
```

## Performance Considerations

### Optimization Tips

1. **Size Pre-check**: Different sized graphs/datasets are never isomorphic
2. **Early Termination**: Non-matching named graph sets exit early
3. **Canonical Caching**: Cache canonical forms for repeated comparisons
4. **Batch Processing**: Process multiple comparisons together when possible

### Scaling Behavior

- **Small Graphs** (< 100 triples): Near-instant comparison
- **Medium Graphs** (100-10,000 triples): Subsecond comparison
- **Large Graphs** (> 10,000 triples): May require seconds, depends on blank node complexity
- **Many Blank Nodes**: Performance degrades with highly interconnected blank node structures

### Memory Usage

- **Canonical Forms**: Temporary memory overhead during comparison
- **Signature Calculation**: O(n) memory for blank node signatures
- **Graph Duplication**: Canonical graphs require additional memory

## Integration with Existing APIs

### With Serializers
```gleam
// N-Triples round-trip validation
let original_graph = my_graph
let ntriples_text = ntriples.serialize_graph(original_graph)
let parsed_graph = ntriples.parse_graph(ntriples_text)

graph.isomorphic(original_graph, parsed_graph) // Should be True
```

### With Graph Operations
```gleam
// Merge operation validation
let graph1 = graph.from_list([triples1])
let graph2 = graph.from_list([triples2])
let merged = graph.merge(into: graph1, from: graph2)

// Verify merge semantics
let expected = graph.from_list(list.append(triples1, triples2))
graph.isomorphic(merged, expected) |> should.be_true()
```

### With Dataset Operations
```gleam
// Dataset merge validation
let dataset1 = dataset.from_list([quads1])
let dataset2 = dataset.from_list([quads2])
let merged = dataset.merge(into: dataset1, from: dataset2)

let expected = dataset.from_list(list.append(quads1, quads2))
dataset.isomorphic(merged, expected) |> should.be_true()
```

## Error Handling

### No Explicit Errors
The isomorphism functions return `Bool` values and do not throw errors. Invalid inputs are handled gracefully:

- **Empty Graphs/Datasets**: Compared correctly (empty = empty)
- **Malformed Structures**: Compared structurally (may not be meaningful)
- **Memory Exhaustion**: May cause system-level errors in extreme cases

### Debugging Tips

1. **Size Mismatch**: Check `graph.size()` or `dataset.quad_count()` first
2. **Named Graph Issues**: Use `dataset.graph_names()` to check graph name sets
3. **Canonical Inspection**: Use `canonicalize()` functions to see normalized forms
4. **Manual Comparison**: Compare `graph.triples()` lists for debugging

## Future Enhancements

### Planned Improvements
- **RDF-star Integration**: Full support for quoted triples in signatures
- **Performance Optimization**: More efficient algorithms for large graphs
- **Incremental Comparison**: Compare only changed portions of graphs
- **Parallel Processing**: Multi-threaded canonicalization for large datasets

### API Extensions
- **Similarity Metrics**: Quantify how "similar" non-isomorphic graphs are
- **Partial Isomorphism**: Find largest isomorphic subgraphs
- **Mapping Extraction**: Return the blank node mapping that creates isomorphism
- **Streaming Comparison**: Compare graphs without loading entirely into memory

## References

- [RDF 1.1 Concepts and Abstract Syntax](https://www.w3.org/TR/rdf11-concepts/)
- [RDF Dataset Normalization](https://www.w3.org/TR/rdf11-concepts/#section-dataset-conneg)
- [Graph Isomorphism in RDF](https://www.w3.org/TR/rdf11-concepts/#graph-isomorphism)
- [RDF-star Specification](https://w3c.github.io/rdf-star/cg-spec/)

The isomorphism functionality provides a solid foundation for semantic RDF comparison while maintaining good performance characteristics for typical use cases.
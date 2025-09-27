import glaph_rdf/statement
import gleam/list

/// An RDF graph containing a collection of RDF triples.
///
/// A graph is an unordered collection of RDF triples with no duplicates.
/// Graphs provide the core structure for organizing RDF statements and
/// support operations like adding, removing, and querying triples.
///
/// ## Examples
/// ```gleam
/// let empty_graph = graph.new()
/// let graph_with_triple = graph.add(empty_graph, some_triple)
/// ```
pub type Graph {
  Graph(triples: List(statement.Triple))
}

/// Create a new empty RDF graph.
///
/// Returns an empty graph with no triples. This is the starting point
/// for building RDF graphs programmatically.
///
/// ## Examples
/// ```gleam
/// let empty_graph = graph.new()
/// graph.size(empty_graph)  // -> 0
/// ```
pub fn new() -> Graph {
  Graph(triples: [])
}

/// Create an RDF graph from a list of triples with automatic deduplication.
///
/// Constructs a graph from the provided list of triples, automatically
/// removing any duplicates to maintain the mathematical properties of
/// RDF graphs as sets.
///
/// ## Examples
/// ```gleam
/// let triples = [triple1, triple2, triple1]  // Contains duplicate
/// let graph = graph.from_list(triples)       // Duplicate removed
/// graph.size(graph)  // -> 2
/// ```
pub fn from_list(triples: List(statement.Triple)) -> Graph {
  Graph(triples: dedupe(triples))
}

/// Extract all triples from an RDF graph as a list.
///
/// Returns the complete collection of triples contained in the graph.
/// The order of triples in the returned list is not guaranteed to be
/// stable across operations.
///
/// ## Examples
/// ```gleam
/// let graph_triples = graph.triples(my_graph)
/// list.length(graph_triples)  // Number of triples in graph
/// ```
pub fn triples(graph: Graph) -> List(statement.Triple) {
  graph.triples
}

/// Get the number of triples in an RDF graph.
///
/// Returns the count of unique triples contained in the graph.
/// This is equivalent to the cardinality of the graph as a mathematical set.
///
/// ## Examples
/// ```gleam
/// let empty = graph.new()
/// graph.size(empty)  // -> 0
/// 
/// let graph_with_data = graph.add(empty, some_triple)
/// graph.size(graph_with_data)  // -> 1
/// ```
pub fn size(graph: Graph) -> Int {
  list.length(graph.triples)
}

/// Check if an RDF graph contains a specific triple.
///
/// Tests whether the given triple exists in the graph. This performs
/// exact matching - all three components (subject, predicate, object)
/// must match exactly, including any RDF-star quoted triples.
///
/// ## Examples
/// ```gleam
/// graph.contains(my_graph, target_triple)  // -> True or False
/// 
/// case graph.contains(my_graph, triple) {
///   True -> // Triple exists in graph
///   False -> // Triple not found
/// }
/// ```
pub fn contains(graph: Graph, triple: statement.Triple) -> Bool {
  list.any(graph.triples, fn(existing) { existing == triple })
}

/// Add a triple to an RDF graph.
///
/// Adds the specified triple to the graph if it's not already present.
/// If the triple already exists, returns the graph unchanged, maintaining
/// the set semantics of RDF graphs (no duplicates).
///
/// ## Examples
/// ```gleam
/// let updated_graph = graph.add(my_graph, new_triple)
/// 
/// let final_graph = 
///   graph.new()
///   |> graph.add(triple1)
///   |> graph.add(triple2)
///   |> graph.add(triple1)  // Won't create duplicate
/// ```
pub fn add(graph: Graph, triple: statement.Triple) -> Graph {
  case contains(graph, triple) {
    True -> graph
    False -> Graph(triples: [triple, ..graph.triples])
  }
}

/// Remove a triple from an RDF graph.
///
/// Removes the specified triple from the graph if it exists. If the triple
/// is not present in the graph, returns the graph unchanged. This operation
/// maintains the integrity of remaining triples.
///
/// ## Examples
/// ```gleam
/// let smaller_graph = graph.remove(my_graph, unwanted_triple)
/// 
/// // Conditional removal
/// let cleaned_graph = case should_remove {
///   True -> graph.remove(my_graph, triple)
///   False -> my_graph
/// }
/// ```
pub fn remove(graph: Graph, triple: statement.Triple) -> Graph {
  Graph(
    triples: list.filter(graph.triples, fn(existing) { existing != triple }),
  )
}

/// Merge two RDF graphs into one.
///
/// Combines all triples from both graphs into a single graph, automatically
/// handling deduplication. This implements the mathematical union of two
/// sets of triples. The order of arguments determines which graph receives
/// the new triples.
///
/// ## Examples
/// ```gleam
/// let combined = graph.merge(into: base_graph, from: additional_graph)
/// 
/// // Chain multiple merges
/// let final_graph = 
///   base_graph
///   |> graph.merge(from: graph1)
///   |> graph.merge(from: graph2)
/// ```
pub fn merge(into graph: Graph, from other: Graph) -> Graph {
  list.fold(other.triples, graph, fn(acc, triple) { add(acc, triple) })
}

fn dedupe(triples: List(statement.Triple)) -> List(statement.Triple) {
  list.reverse(
    list.fold(triples, [], fn(acc, triple) {
      case list.any(acc, fn(existing) { existing == triple }) {
        True -> acc
        False -> [triple, ..acc]
      }
    }),
  )
}

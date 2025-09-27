import glaph_rdf/graph
import glaph_rdf/statement
import glaph_rdf/term
import gleam/list

/// An RDF dataset containing multiple named graphs and a default graph.
///
/// A dataset is a collection of RDF quads (triples with graph names) that
/// can represent multiple separate graphs. This enables working with complex
/// RDF data from multiple sources or contexts, as supported by formats like TriG.
///
/// ## Examples
/// ```gleam
/// let dataset = dataset.new()
/// let dataset_with_triple = dataset.add_triple(dataset, some_triple)
/// let dataset_with_named_graph = dataset.replace_graph(dataset, graph_name, my_graph)
/// ```
pub type Dataset {
  Dataset(quads: List(statement.Quad))
}

/// Create a new empty RDF dataset.
///
/// Returns an empty dataset with no quads. This is the starting point
/// for building RDF datasets that can contain multiple named graphs.
///
/// ## Examples
/// ```gleam
/// let empty_dataset = dataset.new()
/// dataset.quad_count(empty_dataset)  // -> 0
/// ```
pub fn new() -> Dataset {
  Dataset(quads: [])
}

/// Create an RDF dataset from a list of quads with automatic deduplication.
///
/// Constructs a dataset from the provided list of quads, automatically
/// removing any duplicates to maintain the mathematical properties of
/// RDF datasets as sets of quads.
///
/// ## Examples
/// ```gleam
/// let quads = [quad1, quad2, quad1]  // Contains duplicate
/// let dataset = dataset.from_list(quads)  // Duplicate removed
/// dataset.quad_count(dataset)  // -> 2
/// ```
pub fn from_list(quads: List(statement.Quad)) -> Dataset {
  Dataset(quads: dedupe(quads))
}

/// Extract all quads from an RDF dataset as a list.
///
/// Returns the complete collection of quads contained in the dataset.
/// Each quad includes the triple plus its graph name context.
/// The order of quads in the returned list is not guaranteed to be stable.
///
/// ## Examples
/// ```gleam
/// let all_quads = dataset.quads(my_dataset)
/// list.length(all_quads)  // Number of quads in dataset
/// ```
pub fn quads(dataset: Dataset) -> List(statement.Quad) {
  dataset.quads
}

/// Get the number of quads in an RDF dataset.
///
/// Returns the count of unique quads contained in the dataset across
/// all graphs. This includes quads from the default graph and all
/// named graphs.
///
/// ## Examples
/// ```gleam
/// let empty = dataset.new()
/// dataset.quad_count(empty)  // -> 0
/// 
/// let dataset_with_data = dataset.add_triple(empty, some_triple)
/// dataset.quad_count(dataset_with_data)  // -> 1
/// ```
pub fn quad_count(dataset: Dataset) -> Int {
  list.length(dataset.quads)
}

/// Check if an RDF dataset contains a specific quad.
///
/// Tests whether the given quad exists in the dataset. This performs
/// exact matching on all four components: subject, predicate, object,
/// and graph name.
///
/// ## Examples
/// ```gleam
/// dataset.contains_quad(my_dataset, target_quad)  // -> True or False
/// 
/// case dataset.contains_quad(my_dataset, quad) {
///   True -> // Quad exists in dataset
///   False -> // Quad not found
/// }
/// ```
pub fn contains_quad(dataset: Dataset, quad: statement.Quad) -> Bool {
  list.any(dataset.quads, fn(existing) { existing == quad })
}

/// Check if an RDF dataset contains a specific triple in a specific graph.
///
/// Tests whether the given triple exists in the specified graph within
/// the dataset. This is a convenience function that constructs the
/// appropriate quad and checks for its presence.
///
/// ## Examples
/// ```gleam
/// dataset.contains_triple(my_dataset, triple, term.DefaultGraph)
/// // Check if triple exists in default graph
/// 
/// dataset.contains_triple(my_dataset, triple, term.NamedGraph(graph_iri))
/// // Check if triple exists in named graph
/// ```
pub fn contains_triple(
  dataset: Dataset,
  triple: statement.Triple,
  graph_name: term.GraphName,
) -> Bool {
  contains_quad(dataset, statement.quad(triple, graph_name))
}

/// Add a quad to an RDF dataset.
///
/// Adds the specified quad to the dataset if it's not already present.
/// If the quad already exists, returns the dataset unchanged, maintaining
/// the set semantics of RDF datasets (no duplicates).
///
/// ## Examples
/// ```gleam
/// let updated_dataset = dataset.add_quad(my_dataset, new_quad)
/// 
/// let final_dataset = 
///   dataset.new()
///   |> dataset.add_quad(quad1)
///   |> dataset.add_quad(quad2)
///   |> dataset.add_quad(quad1)  // Won't create duplicate
/// ```
pub fn add_quad(dataset: Dataset, quad: statement.Quad) -> Dataset {
  case contains_quad(dataset, quad) {
    True -> dataset
    False -> Dataset(quads: [quad, ..dataset.quads])
  }
}

/// Add a triple to the default graph of an RDF dataset.
///
/// Adds the specified triple to the dataset's default graph. This is
/// a convenience function equivalent to adding a quad with DefaultGraph
/// as the graph name.
///
/// ## Examples
/// ```gleam
/// let dataset_with_triple = dataset.add_triple(my_dataset, new_triple)
/// 
/// // Chaining triple additions to default graph
/// let populated_dataset =
///   dataset.new()
///   |> dataset.add_triple(triple1)
///   |> dataset.add_triple(triple2)
/// ```
pub fn add_triple(dataset: Dataset, triple: statement.Triple) -> Dataset {
  add_quad(dataset, statement.quad(triple, term.DefaultGraph))
}

/// Remove a quad from an RDF dataset.
///
/// Removes the specified quad from the dataset if it exists. If the quad
/// is not present in the dataset, returns the dataset unchanged. This
/// operation maintains the integrity of remaining quads.
///
/// ## Examples
/// ```gleam
/// let smaller_dataset = dataset.remove_quad(my_dataset, unwanted_quad)
/// 
/// // Conditional removal
/// let cleaned_dataset = case should_remove {
///   True -> dataset.remove_quad(my_dataset, quad)
///   False -> my_dataset
/// }
/// ```
pub fn remove_quad(dataset: Dataset, quad: statement.Quad) -> Dataset {
  Dataset(quads: list.filter(dataset.quads, fn(existing) { existing != quad }))
}

/// Remove all quads from a specific graph in an RDF dataset.
///
/// Removes all quads that belong to the specified graph, effectively
/// deleting the entire named graph from the dataset. Other graphs
/// remain unaffected.
///
/// ## Examples
/// ```gleam
/// let dataset_without_graph = dataset.remove_graph(my_dataset, graph_name)
/// 
/// // Remove default graph
/// let no_default = dataset.remove_graph(my_dataset, term.DefaultGraph)
/// ```
pub fn remove_graph(dataset: Dataset, name: term.GraphName) -> Dataset {
  Dataset(quads: list.filter(dataset.quads, fn(quad) { quad.graph != name }))
}

/// Extract the default graph from an RDF dataset.
///
/// Returns a Graph containing all triples from the dataset's default graph.
/// This is a convenience function equivalent to calling `graph()` with
/// `DefaultGraph` as the graph name.
///
/// ## Examples
/// ```gleam
/// let default = dataset.default_graph(my_dataset)
/// let triple_count = graph.size(default)
/// ```
pub fn default_graph(dataset: Dataset) -> graph.Graph {
  graph(dataset, term.DefaultGraph)
}

/// Extract a specific graph from an RDF dataset by name.
///
/// Returns a Graph containing all triples from the specified graph within
/// the dataset. If the graph doesn't exist or has no triples, returns
/// an empty graph.
///
/// ## Examples
/// ```gleam
/// let named_graph = dataset.graph(my_dataset, term.NamedGraph(graph_iri))
/// let default_graph = dataset.graph(my_dataset, term.DefaultGraph)
/// 
/// // Check if a named graph exists and has content
/// let graph_size = graph.size(dataset.graph(my_dataset, graph_name))
/// ```
pub fn graph(dataset: Dataset, name: term.GraphName) -> graph.Graph {
  dataset.quads
  |> list.filter(fn(quad) { quad.graph == name })
  |> list.map(statement.triple_from_quad)
  |> graph.from_list
}

/// Merge two RDF datasets into one.
///
/// Combines all quads from both datasets into a single dataset, automatically
/// handling deduplication. This implements the mathematical union of two
/// sets of quads, preserving all named graphs and the default graph.
///
/// ## Examples
/// ```gleam
/// let combined = dataset.merge(into: base_dataset, from: additional_dataset)
/// 
/// // Chain multiple merges
/// let final_dataset = 
///   base_dataset
///   |> dataset.merge(from: dataset1)
///   |> dataset.merge(from: dataset2)
/// ```
pub fn merge(into dataset: Dataset, from other: Dataset) -> Dataset {
  list.fold(other.quads, dataset, fn(acc, quad) { add_quad(acc, quad) })
}

/// Replace or add a named graph in an RDF dataset.
///
/// Completely replaces the content of the specified graph with the
/// provided new graph. If the graph doesn't exist, it's created.
/// If it exists, all its current triples are removed and replaced
/// with the new graph's triples.
///
/// ## Examples
/// ```gleam
/// let updated_dataset = dataset.replace_graph(
///   my_dataset, 
///   term.NamedGraph(graph_iri), 
///   new_graph_content
/// )
/// 
/// // Replace default graph
/// let updated_default = dataset.replace_graph(
///   my_dataset,
///   term.DefaultGraph,
///   new_default_content
/// )
/// ```
pub fn replace_graph(
  dataset: Dataset,
  name: term.GraphName,
  new_graph: graph.Graph,
) -> Dataset {
  let stripped = remove_graph(dataset, name)

  list.fold(graph.triples(new_graph), stripped, fn(acc, triple) {
    add_quad(acc, statement.quad(triple, name))
  })
}

/// Get all named graph identifiers from an RDF dataset.
///
/// Returns a list of unique graph names present in the dataset, excluding
/// the default graph. This is useful for discovering what named graphs
/// are available in a dataset for iteration or processing.
///
/// ## Examples
/// ```gleam
/// let names = dataset.graph_names(my_dataset)
/// 
/// // Process each named graph
/// list.each(names, fn(name) {
///   let graph_content = dataset.graph(my_dataset, name)
///   // Process graph_content...
/// })
/// ```
pub fn graph_names(dataset: Dataset) -> List(term.GraphName) {
  dataset.quads
  |> list.map(fn(quad) { quad.graph })
  |> list.filter(fn(name) { name != term.DefaultGraph })
  |> dedupe_graph_names
}

fn dedupe(quads: List(statement.Quad)) -> List(statement.Quad) {
  list.reverse(
    list.fold(quads, [], fn(acc, quad) {
      case list.any(acc, fn(existing) { existing == quad }) {
        True -> acc
        False -> [quad, ..acc]
      }
    }),
  )
}

fn dedupe_graph_names(names: List(term.GraphName)) -> List(term.GraphName) {
  list.reverse(
    list.fold(names, [], fn(acc, name) {
      case list.any(acc, fn(existing) { existing == name }) {
        True -> acc
        False -> [name, ..acc]
      }
    }),
  )
}

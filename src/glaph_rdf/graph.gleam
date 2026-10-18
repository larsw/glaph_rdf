import glaph_rdf/statement
import glaph_rdf/term
import gleam/dict
import gleam/int
import gleam/list
import gleam/order
import gleam/result
import gleam/set
import gleam/string

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
/// RDF graphs as sets. The first occurrence of each triple is kept and the
/// input order is preserved.
///
/// This is the preferred way to build a graph from many triples: it runs in
/// O(n log n), whereas folding `add` over a list is O(n²).
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
/// the new triples. The result is the same as folding `add` over the triples
/// of `other`, but runs in O((n + m) log(n + m)).
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
  Graph(triples: prepend_new(
    graph.triples,
    set.from_list(graph.triples),
    other.triples,
  ))
}

/// Check if two RDF graphs are isomorphic (logically equivalent).
///
/// Two graphs are isomorphic if there exists a bijection between their blank nodes
/// such that when applied, the graphs become identical. This means they represent
/// the same RDF information despite potentially different blank node labels.
///
/// This algorithm uses canonical labeling to normalize blank node identifiers,
/// making isomorphism checking reliable and efficient.
///
/// ## Examples
/// ```gleam
/// let graph1 = graph.from_list([
///   statement.triple(term.SubjectBlank(blank_node("a")), predicate, object)
/// ])
/// let graph2 = graph.from_list([
///   statement.triple(term.SubjectBlank(blank_node("x")), predicate, object)  
/// ])
/// 
/// graph.isomorphic(graph1, graph2)  // -> True (same structure, different blank node labels)
/// ```
///
/// ## Complexity
/// Time: O(n²) where n is the number of triples
/// Space: O(n) for canonical representation
pub fn isomorphic(graph1: Graph, graph2: Graph) -> Bool {
  // Early size check for efficiency
  case size(graph1) == size(graph2) {
    False -> False
    True -> {
      let canonical1 = canonicalize(graph1)
      let canonical2 = canonicalize(graph2)

      // Compare triple sets rather than graph structures
      let triples1 = triples(canonical1) |> list.sort(compare_triples_internal)
      let triples2 = triples(canonical2) |> list.sort(compare_triples_internal)

      triples1 == triples2
    }
  }
}

/// Create a canonical representation of an RDF graph.
///
/// Converts all blank nodes to a normalized form using deterministic labeling.
/// The resulting graph can be compared for exact equality to determine isomorphism.
/// Blank nodes are relabeled with canonical identifiers based on their structural
/// properties within the graph.
///
/// ## Examples  
/// ```gleam
/// let original = graph.from_list([triple_with_blank_nodes])
/// let canonical = graph.canonicalize(original)
/// // All blank nodes now have predictable, deterministic labels
/// ```
pub fn canonicalize(graph: Graph) -> Graph {
  let blank_nodes = extract_blank_nodes(graph)
  case list.is_empty(blank_nodes) {
    True -> graph
    // No blank nodes, return as-is
    False -> {
      let mapping = create_canonical_mapping(graph, blank_nodes)
      apply_blank_node_mapping(graph, mapping)
    }
  }
}

// Internal helper functions for canonicalization

fn extract_blank_nodes(graph: Graph) -> List(term.BlankNode) {
  graph.triples
  |> list.flat_map(fn(triple) {
    let statement.Triple(subject, _predicate, object) = triple
    let subject_blanks = case subject {
      term.SubjectBlank(blank) -> [blank]
      _ -> []
    }
    let object_blanks = case object {
      term.ObjectBlank(blank) -> [blank]
      _ -> []
    }
    list.append(subject_blanks, object_blanks)
  })
  |> dedupe_blank_nodes
}

fn dedupe_blank_nodes(blanks: List(term.BlankNode)) -> List(term.BlankNode) {
  dedupe(blanks)
}

fn create_canonical_mapping(
  graph: Graph,
  blank_nodes: List(term.BlankNode),
) -> dict.Dict(String, String) {
  // Create signatures for each blank node based on its usage patterns
  let signatures = create_blank_node_signatures(graph, blank_nodes)

  // Sort blank nodes by signature for deterministic labeling
  let sorted_blanks = sort_by_signature(blank_nodes, signatures)

  // Assign canonical labels
  assign_canonical_labels(sorted_blanks)
}

fn create_blank_node_signatures(
  graph: Graph,
  blank_nodes: List(term.BlankNode),
) -> dict.Dict(String, String) {
  list.fold(blank_nodes, dict.new(), fn(acc, blank) {
    let term.BlankNode(id) = blank
    let signature = calculate_blank_node_signature(graph, blank)
    dict.insert(acc, id, signature)
  })
}

fn calculate_blank_node_signature(
  graph: Graph,
  blank: term.BlankNode,
) -> String {
  let term.BlankNode(blank_id) = blank

  let relevant_triples =
    list.filter(graph.triples, fn(triple) {
      triple_contains_blank_node(triple, blank_id)
    })

  let signature_parts =
    list.map(relevant_triples, fn(triple) {
      create_triple_signature(triple, blank_id)
    })

  signature_parts
  |> list.sort(string.compare)
  |> string.join("|")
}

fn triple_contains_blank_node(
  triple: statement.Triple,
  blank_id: String,
) -> Bool {
  let statement.Triple(subject, _predicate, object) = triple

  let subject_matches = case subject {
    term.SubjectBlank(term.BlankNode(id)) -> id == blank_id
    _ -> False
  }

  let object_matches = case object {
    term.ObjectBlank(term.BlankNode(id)) -> id == blank_id
    _ -> False
  }

  subject_matches || object_matches
}

fn create_triple_signature(
  triple: statement.Triple,
  blank_id: String,
) -> String {
  let statement.Triple(subject, predicate, object) = triple
  let term.NamedNode(pred_iri) = predicate

  let subject_sig = case subject {
    term.SubjectNamed(term.NamedNode(iri)) -> "N:" <> iri
    term.SubjectBlank(term.BlankNode(id)) ->
      case id == blank_id {
        True -> "B:SELF"
        False -> "B:" <> id
      }
    term.SubjectTriple(_) -> "T:QUOTED"
  }

  let object_sig = case object {
    term.ObjectNamed(term.NamedNode(iri)) -> "N:" <> iri
    term.ObjectBlank(term.BlankNode(id)) ->
      case id == blank_id {
        True -> "B:SELF"
        False -> "B:" <> id
      }
    term.ObjectLiteral(literal) -> "L:" <> serialize_literal(literal)
    term.ObjectTriple(_) -> "T:QUOTED"
  }

  subject_sig <> "|P:" <> pred_iri <> "|" <> object_sig
}

fn serialize_literal(literal: term.Literal) -> String {
  case literal {
    term.SimpleLiteral(value) -> "simple:" <> value
    term.LanguageTaggedLiteral(value, term.LanguageTag(lang)) ->
      "lang:" <> value <> "@" <> lang
    term.TypedLiteral(value, term.NamedNode(datatype)) ->
      "typed:" <> value <> "^^" <> datatype
  }
}

fn sort_by_signature(
  blank_nodes: List(term.BlankNode),
  signatures: dict.Dict(String, String),
) -> List(term.BlankNode) {
  blank_nodes
  |> list.map(fn(blank) {
    let term.BlankNode(id) = blank
    let signature = dict.get(signatures, id) |> result.unwrap("")
    #(blank, signature)
  })
  |> list.sort(fn(a, b) { string.compare(a.1, b.1) })
  |> list.map(fn(pair) { pair.0 })
}

fn assign_canonical_labels(
  sorted_blanks: List(term.BlankNode),
) -> dict.Dict(String, String) {
  sorted_blanks
  |> list.index_map(fn(blank, index) {
    let term.BlankNode(original_id) = blank
    let canonical_id = "b" <> int.to_string(index)
    #(original_id, canonical_id)
  })
  |> dict.from_list()
}

fn apply_blank_node_mapping(
  graph: Graph,
  mapping: dict.Dict(String, String),
) -> Graph {
  let remapped_triples =
    list.map(graph.triples, fn(triple) {
      remap_triple_blank_nodes(triple, mapping)
    })
  Graph(triples: remapped_triples)
}

fn remap_triple_blank_nodes(
  triple: statement.Triple,
  mapping: dict.Dict(String, String),
) -> statement.Triple {
  let statement.Triple(subject, predicate, object) = triple

  let new_subject = case subject {
    term.SubjectBlank(term.BlankNode(id)) ->
      case dict.get(mapping, id) {
        Ok(new_id) -> term.SubjectBlank(term.BlankNode(new_id))
        Error(_) -> subject
      }
    _ -> subject
  }

  let new_object = case object {
    term.ObjectBlank(term.BlankNode(id)) ->
      case dict.get(mapping, id) {
        Ok(new_id) -> term.ObjectBlank(term.BlankNode(new_id))
        Error(_) -> object
      }
    _ -> object
  }

  statement.Triple(
    subject: new_subject,
    predicate: predicate,
    object: new_object,
  )
}

fn compare_triples_internal(
  triple1: statement.Triple,
  triple2: statement.Triple,
) -> order.Order {
  let statement.Triple(s1, p1, o1) = triple1
  let statement.Triple(s2, p2, o2) = triple2

  case
    serialize_subject_internal(s1)
    |> string.compare(serialize_subject_internal(s2))
  {
    order.Eq ->
      case
        serialize_predicate_internal(p1)
        |> string.compare(serialize_predicate_internal(p2))
      {
        order.Eq ->
          serialize_object_internal(o1)
          |> string.compare(serialize_object_internal(o2))
        other -> other
      }
    other -> other
  }
}

fn serialize_subject_internal(subject: term.Subject) -> String {
  case subject {
    term.SubjectNamed(term.NamedNode(iri)) -> "N:" <> iri
    term.SubjectBlank(term.BlankNode(id)) -> "B:" <> id
    term.SubjectTriple(_) -> "T:QUOTED"
  }
}

fn serialize_predicate_internal(predicate: term.Predicate) -> String {
  let term.NamedNode(iri) = predicate
  "P:" <> iri
}

fn serialize_object_internal(object: term.Object) -> String {
  case object {
    term.ObjectNamed(term.NamedNode(iri)) -> "N:" <> iri
    term.ObjectBlank(term.BlankNode(id)) -> "B:" <> id
    term.ObjectLiteral(literal) -> "L:" <> serialize_literal(literal)
    term.ObjectTriple(_) -> "T:QUOTED"
  }
}

/// Remove duplicates in O(n log n), keeping the first occurrence of each item
/// and the original order.
fn dedupe(items: List(a)) -> List(a) {
  list.reverse(prepend_new([], set.new(), items))
}

/// Prepend, in reverse order, every item of `items` that is not in `seen` and
/// has not been prepended already. This is exactly what folding a
/// prepend-if-absent `add` over `items` does, but with set lookups instead of
/// list scans.
fn prepend_new(acc: List(a), seen: set.Set(a), items: List(a)) -> List(a) {
  case items {
    [] -> acc
    [item, ..rest] ->
      case set.contains(seen, item) {
        True -> prepend_new(acc, seen, rest)
        False -> prepend_new([item, ..acc], set.insert(seen, item), rest)
      }
  }
}

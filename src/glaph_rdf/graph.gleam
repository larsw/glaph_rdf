import glaph_rdf/statement
import glaph_rdf/term
import gleam/dict
import gleam/int
import gleam/list
import gleam/option
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
/// Blank nodes nested inside triple terms are part of the same bijection as
/// blank nodes in subject and object position.
///
/// The check is exact. Blank nodes are first partitioned by iterative colour
/// refinement (each blank node is described by the statements it occurs in,
/// with every term, literal and nested triple term encoded unambiguously and
/// other blank nodes replaced by their current colour). When the refinement
/// leaves several blank nodes indistinguishable, the candidates are tried one
/// by one, and every candidate bijection is verified against the other graph.
/// Separate blank-node components are matched one pair at a time, and a
/// candidate is skipped when an automorphism of the second graph maps a
/// candidate that already failed onto it, so interchangeable blank nodes are
/// not tried in every order.
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
/// Refinement is incremental (only blank nodes next to a colour change are
/// revisited, and the largest part of a split class keeps its colour), so it
/// typically costs about O(n log n) in the size of the statements that mention
/// blank nodes. Graphs that refinement cannot split need backtracking; the
/// component split and the automorphism pruning keep symmetric parts cheap,
/// but the search is still exponential in the worst case.
pub fn isomorphic(graph1: Graph, graph2: Graph) -> Bool {
  quads_isomorphic(
    list.map(graph1.triples, default_graph_quad),
    list.map(graph2.triples, default_graph_quad),
  )
}

/// Create a canonical representation of an RDF graph.
///
/// Relabels every blank node, including blank nodes nested inside triple
/// terms, to `b0`, `b1`, ... The labels depend only on the structure of the
/// graph, not on the original labels, so isomorphic graphs normally get the
/// same triples (compare them as sets: the triple order is kept). For graphs
/// with symmetries that colour refinement cannot resolve the labelling may
/// still differ between isomorphic inputs, so use `isomorphic` for a
/// definitive answer.
///
/// ## Examples
/// ```gleam
/// let original = graph.from_list([triple_with_blank_nodes])
/// let canonical = graph.canonicalize(original)
/// // All blank nodes now have predictable, deterministic labels
/// ```
pub fn canonicalize(graph: Graph) -> Graph {
  let quads =
    graph.triples
    |> list.map(default_graph_quad)
    |> canonicalize_quads
  Graph(triples: list.map(quads, statement.triple_from_quad))
}

fn default_graph_quad(triple: statement.Triple) -> statement.Quad {
  statement.quad_from_triple(triple, term.DefaultGraph)
}

// Isomorphism core, shared with `glaph_rdf/dataset` -------------------------

/// Whether two collections of quads (taken as sets) are equal up to a single
/// bijection between their blank nodes. The bijection covers blank nodes in
/// every position: subject, object, graph name and anywhere inside (nested)
/// triple terms. Used by `isomorphic` here and in `glaph_rdf/dataset`.
@internal
pub fn quads_isomorphic(
  quads1: List(statement.Quad),
  quads2: List(statement.Quad),
) -> Bool {
  let set1 = set.from_list(quads1)
  let set2 = set.from_list(quads2)
  case set.size(set1) == set.size(set2) {
    False -> False
    True -> {
      let #(blank1, ground1) = list.partition(set.to_list(set1), quad_has_blank)
      let #(blank2, _ground2) =
        list.partition(set.to_list(set2), quad_has_blank)
      // Equal sizes plus ground1 ⊆ set2 means the ground parts are equal,
      // because a ground quad can never equal a quad with a blank node.
      case
        list.length(blank1) == list.length(blank2)
        && list.all(ground1, set.contains(set2, _))
      {
        False -> False
        True -> {
          let coloring = new_coloring(blank1, blank2)
          let #(size1, size2) = class_size(coloring, 0)
          case size1 == size2 {
            False -> False
            True -> start_search(coloring, blank1, blank2, set2)
          }
        }
      }
    }
  }
}

/// Relabel every blank node of `quads` (in every position, including inside
/// triple terms and graph names) to `b0`, `b1`, ... based on structure only.
/// The quad order is kept. Used by `canonicalize` here and in
/// `glaph_rdf/dataset`.
@internal
pub fn canonicalize_quads(quads: List(statement.Quad)) -> List(statement.Quad) {
  case list.filter(quads, quad_has_blank) {
    [] -> quads
    blank_quads -> {
      let coloring = new_coloring(blank_quads, [])
      let coloring = canonical_coloring(coloring, initial_dirty(coloring))
      // Final colours are distinct but not contiguous: label by rank.
      let labels =
        coloring.colors
        |> dict.to_list
        |> list.sort(fn(a, b) { int.compare(a.1, b.1) })
        |> list.index_map(fn(entry, index) {
          #({ entry.0 }.id, "b" <> int.to_string(index))
        })
        |> dict.from_list
      list.map(quads, fn(quad) {
        remap_quad(quad, fn(id) {
          case dict.get(labels, id) {
            Ok(label) -> label
            Error(Nil) -> id
          }
        })
      })
    }
  }
}

/// A blank node of one of the two sides being compared (`first` is True for
/// the first side). `canonicalize` only uses the first side.
type Key {
  Key(first: Bool, id: String)
}

/// Colour refinement state over both sides at once, so that equal colours
/// mean the same thing on both sides.
type Coloring {
  Coloring(
    /// Statement templates mentioning each blank node (once per statement).
    templates: dict.Dict(Key, List(List(Chunk))),
    /// Blank nodes sharing a statement with each blank node (same side).
    neighbors: dict.Dict(Key, List(Key)),
    colors: dict.Dict(Key, Int),
    /// Number of members of each colour class on the first and second side.
    sizes: dict.Dict(Int, #(Int, Int)),
    /// Members of each colour class.
    classes: dict.Dict(Int, set.Set(Key)),
    /// The signature every member of a class had after the last round.
    signatures: dict.Dict(Int, String),
    next_color: Int,
  )
}

fn new_coloring(
  quads1: List(statement.Quad),
  quads2: List(statement.Quad),
) -> Coloring {
  let empty = #(dict.new(), dict.new())
  let #(templates, neighbors) =
    index_side(quads2, False, index_side(quads1, True, empty))
  let colors = dict.map_values(templates, fn(_, _) { 0 })
  let sizes =
    dict.fold(colors, #(0, 0), fn(acc, key, _) { add_member(acc, key, 1) })
  Coloring(
    templates: templates,
    neighbors: dict.map_values(neighbors, fn(_, keys) { dedupe(keys) }),
    colors: colors,
    sizes: dict.from_list([#(0, sizes)]),
    classes: dict.from_list([#(0, set.from_list(dict.keys(colors)))]),
    signatures: dict.new(),
    next_color: 1,
  )
}

fn index_side(
  quads: List(statement.Quad),
  first: Bool,
  acc: #(dict.Dict(Key, List(List(Chunk))), dict.Dict(Key, List(Key))),
) -> #(dict.Dict(Key, List(List(Chunk))), dict.Dict(Key, List(Key))) {
  list.fold(quads, acc, fn(acc, quad) {
    let template = quad_template(quad)
    let keys =
      quad
      |> quad_blank_ids
      |> dedupe
      |> list.map(Key(first, _))
    list.fold(keys, acc, fn(acc, key) {
      let #(templates, neighbors) = acc
      let others = list.filter(keys, fn(other) { other != key })
      #(
        dict.upsert(templates, key, fn(existing) {
          [template, ..option.unwrap(existing, [])]
        }),
        dict.upsert(neighbors, key, fn(existing) {
          list.append(others, option.unwrap(existing, []))
        }),
      )
    })
  })
}

fn add_member(sizes: #(Int, Int), key: Key, amount: Int) -> #(Int, Int) {
  case key.first {
    True -> #(sizes.0 + amount, sizes.1)
    False -> #(sizes.0, sizes.1 + amount)
  }
}

fn class_size(coloring: Coloring, color: Int) -> #(Int, Int) {
  dict.get(coloring.sizes, color) |> result.unwrap(#(0, 0))
}

fn initial_dirty(coloring: Coloring) -> List(Key) {
  dict.keys(coloring.colors)
}

/// What a search compares: the blank-node statements of the first side, all
/// statements of the second side (for verification), the blank-node
/// statements of the second side, and the refined colouring of the second
/// side against itself (the starting point for automorphism searches).
type Problem {
  Problem(
    quads1: List(statement.Quad),
    target: set.Set(statement.Quad),
    quads2: List(statement.Quad),
    automorphisms: Coloring,
  )
}

/// Refine the initial colouring and verify it, or start the branching search
/// if refinement leaves some blank nodes indistinguishable.
fn start_search(
  coloring: Coloring,
  quads1: List(statement.Quad),
  quads2: List(statement.Quad),
  target: set.Set(statement.Quad),
) -> Bool {
  case refine(coloring, initial_dirty(coloring), True) {
    Error(Nil) -> False
    Ok(coloring) ->
      case ambiguous_class(coloring) {
        Error(Nil) -> result.is_ok(verify(coloring, quads1, target))
        Ok(_) -> {
          let components1 = components(coloring, quads1, True)
          let components2 = components(coloring, quads2, False)
          case components1, components2 {
            [_], [_] -> {
              let automorphisms = new_coloring(quads2, quads2)
              let assert Ok(automorphisms) =
                refine(automorphisms, initial_dirty(automorphisms), True)
              let problem = Problem(quads1:, target:, quads2:, automorphisms:)
              result.is_ok(search(problem, coloring, [], []))
            }
            _, _ ->
              list.length(components1) == list.length(components2)
              && match_components(components1, group_components(components2))
          }
        }
      }
  }
}

/// A connected component of the blank nodes of one side (blank nodes are
/// connected when they share a statement), as its statements plus an
/// invariant: the sorted refined colours of its blank nodes. Isomorphic
/// components have equal invariants.
type Component {
  Component(invariant: List(Int), quads: List(statement.Quad))
}

/// Split one side into connected components. Two inputs are isomorphic
/// exactly when their components can be paired up into isomorphic pairs, so
/// each component is compared on its own. This keeps unrelated symmetric
/// parts (identical components) from multiplying the search.
fn components(
  coloring: Coloring,
  quads: List(statement.Quad),
  first: Bool,
) -> List(Component) {
  let roots =
    list.fold(quads, dict.new(), fn(roots, quad) {
      list.fold(quad_blank_ids(quad), roots, fn(roots, id) {
        case dict.has_key(roots, id) {
          True -> roots
          False -> mark_component(coloring, first, [id], id, roots)
        }
      })
    })
  list.fold(quads, dict.new(), fn(groups, quad) {
    let assert [id, ..] = quad_blank_ids(quad)
    let assert Ok(root) = dict.get(roots, id)
    dict.upsert(groups, root, fn(existing) {
      [quad, ..option.unwrap(existing, [])]
    })
  })
  |> dict.to_list
  |> list.map(fn(entry) {
    let invariant =
      entry.1
      |> list.flat_map(quad_blank_ids)
      |> dedupe
      |> list.map(fn(id) { color_of(coloring, Key(first, id)) })
      |> list.sort(int.compare)
    Component(invariant:, quads: entry.1)
  })
}

/// Depth-first walk assigning `root` to every blank node reachable from
/// `stack`.
fn mark_component(
  coloring: Coloring,
  first: Bool,
  stack: List(String),
  root: String,
  roots: dict.Dict(String, String),
) -> dict.Dict(String, String) {
  case stack {
    [] -> roots
    [id, ..rest] ->
      case dict.has_key(roots, id) {
        True -> mark_component(coloring, first, rest, root, roots)
        False -> {
          let next =
            dict.get(coloring.neighbors, Key(first, id))
            |> result.unwrap([])
            |> list.map(fn(key) { key.id })
          mark_component(
            coloring,
            first,
            list.append(next, rest),
            root,
            dict.insert(roots, id, root),
          )
        }
      }
  }
}

fn group_components(
  components: List(Component),
) -> dict.Dict(List(Int), List(Component)) {
  list.fold(components, dict.new(), fn(groups, component) {
    dict.upsert(groups, component.invariant, fn(existing) {
      [component, ..option.unwrap(existing, [])]
    })
  })
}

/// Pair every first-side component with an isomorphic, still unused
/// second-side component. Isomorphism is an equivalence relation, so taking
/// the first isomorphic match is always safe.
fn match_components(
  components: List(Component),
  unused: dict.Dict(List(Int), List(Component)),
) -> Bool {
  case components {
    [] -> True
    [component, ..rest] -> {
      let candidates =
        dict.get(unused, component.invariant) |> result.unwrap([])
      case take_isomorphic(component, candidates, []) {
        Error(Nil) -> False
        Ok(remaining) ->
          match_components(
            rest,
            dict.insert(unused, component.invariant, remaining),
          )
      }
    }
  }
}

fn take_isomorphic(
  component: Component,
  candidates: List(Component),
  skipped: List(Component),
) -> Result(List(Component), Nil) {
  case candidates {
    [] -> Error(Nil)
    [candidate, ..rest] ->
      case quads_isomorphic(component.quads, candidate.quads) {
        True -> Ok(list.append(skipped, rest))
        False -> take_isomorphic(component, rest, [candidate, ..skipped])
      }
  }
}

/// Refine, then either verify the unique candidate bijection or branch on
/// the smallest colour class that is still ambiguous. `fixed` lists the
/// second-side blank nodes individualised so far. Returns the bijection
/// (first-side label to second-side label) when one is found.
fn search(
  problem: Problem,
  coloring: Coloring,
  dirty: List(Key),
  fixed: List(String),
) -> Result(dict.Dict(String, String), Nil) {
  use coloring <- result.try(refine(coloring, dirty, True))
  case ambiguous_class(coloring) {
    Error(Nil) -> verify(coloring, problem.quads1, problem.target)
    Ok(color) -> {
      let #(members1, members2) =
        members(coloring, color) |> list.partition(fn(key) { key.first })
      let assert [chosen, ..] = members1
      let candidates =
        members2
        |> list.map(fn(key) { key.id })
        |> list.sort(string.compare)
      try_candidates(
        problem,
        coloring,
        fixed,
        chosen,
        candidates,
        candidates,
        [],
        dict.new(),
      )
    }
  }
}

/// Try mapping `chosen` to each candidate in turn, with orbit pruning: when
/// candidate `y` failed and some automorphism of the second side fixes every
/// node in `fixed` and maps `y` to a later candidate `z`, then `z` must fail
/// too and is skipped. `orbits` is a union-find over the candidates, merged
/// with every automorphism found so far; `failed` holds the candidates that
/// failed.
fn try_candidates(
  problem: Problem,
  coloring: Coloring,
  fixed: List(String),
  chosen: Key,
  all: List(String),
  candidates: List(String),
  failed: List(String),
  orbits: dict.Dict(String, String),
) -> Result(dict.Dict(String, String), Nil) {
  case candidates {
    [] -> Error(Nil)
    [candidate, ..rest] -> {
      let #(skip, orbits) =
        same_orbit_as_failed(problem, fixed, all, candidate, failed, orbits)
      case skip {
        True ->
          try_candidates(
            problem,
            coloring,
            fixed,
            chosen,
            all,
            rest,
            failed,
            orbits,
          )
        False -> {
          let #(next, dirty) =
            individualize(coloring, [chosen, Key(False, candidate)])
          case search(problem, next, dirty, [candidate, ..fixed]) {
            Ok(mapping) -> Ok(mapping)
            Error(Nil) ->
              try_candidates(
                problem,
                coloring,
                fixed,
                chosen,
                all,
                rest,
                [candidate, ..failed],
                orbits,
              )
          }
        }
      }
    }
  }
}

/// Whether `candidate` is known to be, or can be shown to be, in the same
/// orbit as a failed candidate under the automorphisms of the second side
/// that fix `fixed` pointwise.
fn same_orbit_as_failed(
  problem: Problem,
  fixed: List(String),
  all: List(String),
  candidate: String,
  failed: List(String),
  orbits: dict.Dict(String, String),
) -> #(Bool, dict.Dict(String, String)) {
  let root = find_root(orbits, candidate)
  let failed_roots = list.map(failed, find_root(orbits, _)) |> dedupe
  case list.contains(failed_roots, root) {
    True -> #(True, orbits)
    False ->
      list.fold_until(failed_roots, #(False, orbits), fn(acc, failed_root) {
        case automorphism(problem, fixed, failed_root, candidate) {
          Error(Nil) -> list.Continue(acc)
          Ok(sigma) -> {
            let orbits =
              list.fold(all, acc.1, fn(orbits, node) {
                case dict.get(sigma, node) {
                  Ok(image) -> union(orbits, node, image)
                  Error(Nil) -> orbits
                }
              })
            list.Stop(#(True, orbits))
          }
        }
      })
  }
}

/// Search for an automorphism of the second side that fixes every node in
/// `fixed` and maps `from` to `to`.
fn automorphism(
  problem: Problem,
  fixed: List(String),
  from: String,
  to: String,
) -> Result(dict.Dict(String, String), Nil) {
  let pairs = [#(from, to), ..list.map(fixed, fn(node) { #(node, node) })]
  let #(coloring, dirty) =
    list.fold(pairs, #(problem.automorphisms, []), fn(acc, pair) {
      let #(coloring, dirty) =
        individualize(acc.0, [Key(True, pair.0), Key(False, pair.1)])
      #(coloring, list.append(dirty, acc.1))
    })
  search(Problem(..problem, quads1: problem.quads2), coloring, dedupe(dirty), [
    to,
    ..fixed
  ])
}

fn find_root(orbits: dict.Dict(String, String), node: String) -> String {
  case dict.get(orbits, node) {
    Ok(parent) if parent != node -> find_root(orbits, parent)
    _ -> node
  }
}

fn union(
  orbits: dict.Dict(String, String),
  a: String,
  b: String,
) -> dict.Dict(String, String) {
  let root_a = find_root(orbits, a)
  let root_b = find_root(orbits, b)
  case root_a == root_b {
    True -> orbits
    False -> dict.insert(orbits, root_b, root_a)
  }
}

/// Every colour class is a singleton on each side: map each blank node of the
/// first side to the blank node of the second side with the same colour and
/// check the result.
fn verify(
  coloring: Coloring,
  quads1: List(statement.Quad),
  target: set.Set(statement.Quad),
) -> Result(dict.Dict(String, String), Nil) {
  let by_color =
    dict.fold(coloring.colors, dict.new(), fn(acc, key, color) {
      case key.first {
        True -> acc
        False -> dict.insert(acc, color, key.id)
      }
    })
  let mapping =
    dict.fold(coloring.colors, dict.new(), fn(acc, key, color) {
      case key.first {
        False -> acc
        True -> {
          let assert Ok(id) = dict.get(by_color, color)
          dict.insert(acc, key.id, id)
        }
      }
    })
  let valid =
    list.all(quads1, fn(quad) {
      let mapped =
        remap_quad(quad, fn(id) {
          let assert Ok(target_id) = dict.get(mapping, id)
          target_id
        })
      set.contains(target, mapped)
    })
  case valid {
    True -> Ok(mapping)
    False -> Error(Nil)
  }
}

/// Canonical labelling of the first side: refine, then repeatedly
/// individualise one member of the smallest ambiguous class (chosen by label,
/// which only matters for symmetries refinement cannot resolve).
fn canonical_coloring(coloring: Coloring, dirty: List(Key)) -> Coloring {
  let assert Ok(coloring) = refine(coloring, dirty, False)
  case ambiguous_class(coloring) {
    Error(Nil) -> coloring
    Ok(color) -> {
      let assert [chosen, ..] =
        members(coloring, color)
        |> list.sort(fn(a, b) { string.compare(a.id, b.id) })
      let #(coloring, dirty) = individualize(coloring, [chosen])
      canonical_coloring(coloring, dirty)
    }
  }
}

/// Incremental colour refinement. A blank node's signature is the sorted
/// encodings of its statements, with itself written as "s" and every other
/// blank node as its current colour. Only `dirty` blank nodes (those whose
/// colour or a neighbour's colour changed) can have a new signature; the
/// others in a class all still share the class signature. Each class with
/// dirty members is split by signature: the members that kept the class
/// signature keep the colour and every other group gets a fresh colour, in
/// signature order, so the colours never depend on blank node labels.
///
/// With `balanced`, every split must leave as many members on each side, or
/// the sides cannot be isomorphic and the result is an error.
fn refine(
  coloring: Coloring,
  dirty: List(Key),
  balanced: Bool,
) -> Result(Coloring, Nil) {
  case dirty {
    [] -> Ok(coloring)
    _ -> {
      let by_class =
        list.fold(dirty, dict.new(), fn(acc, key) {
          let entry = #(key, signature(coloring, key))
          dict.upsert(acc, color_of(coloring, key), fn(existing) {
            [entry, ..option.unwrap(existing, [])]
          })
        })
        |> dict.to_list
        |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
      let split =
        list.try_fold(by_class, #(coloring, []), fn(acc, class) {
          split_class(acc.0, acc.1, class.0, class.1, balanced)
        })
      case split {
        Error(Nil) -> Error(Nil)
        Ok(#(coloring, changed)) ->
          refine(coloring, spread(coloring, changed), balanced)
      }
    }
  }
}

fn split_class(
  coloring: Coloring,
  changed: List(Key),
  color: Int,
  entries: List(#(Key, String)),
  balanced: Bool,
) -> Result(#(Coloring, List(Key)), Nil) {
  let dirty_groups =
    list.fold(entries, dict.new(), fn(acc, entry) {
      dict.upsert(acc, entry.1, fn(existing) {
        [entry.0, ..option.unwrap(existing, [])]
      })
    })
  let #(size1, size2) = class_size(coloring, color)
  let clean_count = size1 + size2 - list.length(entries)
  // Members that are not dirty still share the class signature. They are
  // only listed if their group has to move.
  let clean_signature = case clean_count > 0 {
    True -> dict.get(coloring.signatures, color)
    False -> Error(Nil)
  }
  let groups =
    case clean_signature {
      Ok(signature) ->
        dict.upsert(dirty_groups, signature, fn(existing) {
          option.unwrap(existing, [])
        })
      Error(Nil) -> dirty_groups
    }
    |> dict.to_list
    |> list.map(fn(group) {
      let count = case clean_signature == Ok(group.0) {
        True -> list.length(group.1) + clean_count
        False -> list.length(group.1)
      }
      #(group.0, group.1, count)
    })
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  // The largest group (ties: smallest signature) keeps the colour, so each
  // blank node changes colour O(log n) times and refinement stays fast.
  let assert [first, ..rest] = groups
  let kept =
    list.fold(rest, first, fn(best, group) {
      case group.2 > best.2 {
        True -> group
        False -> best
      }
    })
  let coloring =
    Coloring(
      ..coloring,
      signatures: dict.insert(coloring.signatures, color, kept.0),
    )
  let #(coloring, changed, touched) =
    list.fold(groups, #(coloring, changed, [color]), fn(acc, group) {
      let #(coloring, changed, touched) = acc
      let #(group_signature, keys, _) = group
      case group_signature == kept.0 {
        True -> acc
        False -> {
          let fresh = coloring.next_color
          let keys = case clean_signature == Ok(group_signature) {
            False -> keys
            True -> {
              let dirty =
                set.from_list(list.map(entries, fn(entry) { entry.0 }))
              class_members(coloring, color)
              |> set.filter(fn(key) { !set.contains(dirty, key) })
              |> set.to_list
              |> list.append(keys)
            }
          }
          let coloring =
            list.fold(keys, coloring, fn(coloring, key) {
              move(coloring, key, color, fresh)
            })
          let coloring =
            Coloring(
              ..coloring,
              signatures: dict.insert(
                coloring.signatures,
                fresh,
                group_signature,
              ),
              next_color: fresh + 1,
            )
          #(coloring, list.append(keys, changed), [fresh, ..touched])
        }
      }
    })
  let unbalanced =
    balanced
    && list.any(touched, fn(touched_color) {
      let #(size1, size2) = class_size(coloring, touched_color)
      size1 != size2
    })
  case unbalanced {
    True -> Error(Nil)
    False -> Ok(#(coloring, changed))
  }
}

/// Move one blank node from class `from` to class `to`.
fn move(coloring: Coloring, key: Key, from: Int, to: Int) -> Coloring {
  let sizes =
    coloring.sizes
    |> dict.insert(from, add_member(class_size(coloring, from), key, -1))
    |> dict.insert(to, add_member(class_size(coloring, to), key, 1))
  let classes =
    coloring.classes
    |> dict.insert(from, set.delete(class_members(coloring, from), key))
    |> dict.insert(to, set.insert(class_members(coloring, to), key))
  Coloring(
    ..coloring,
    colors: dict.insert(coloring.colors, key, to),
    sizes: sizes,
    classes: classes,
  )
}

fn class_members(coloring: Coloring, color: Int) -> set.Set(Key) {
  dict.get(coloring.classes, color) |> result.unwrap(set.new())
}

/// The blank nodes whose signature may change after `changed` got new
/// colours: the changed blank nodes and their neighbours.
fn spread(coloring: Coloring, changed: List(Key)) -> List(Key) {
  changed
  |> list.flat_map(fn(key) {
    [key, ..dict.get(coloring.neighbors, key) |> result.unwrap([])]
  })
  |> dedupe
}

fn signature(coloring: Coloring, key: Key) -> String {
  let label = fn(other) {
    case other == key.id {
      True -> "s"
      False ->
        "c" <> int.to_string(color_of(coloring, Key(key.first, other))) <> ";"
    }
  }
  dict.get(coloring.templates, key)
  |> result.unwrap([])
  |> list.map(fill_template(_, label))
  |> list.sort(string.compare)
  |> string.concat
}

fn color_of(coloring: Coloring, key: Key) -> Int {
  let assert Ok(color) = dict.get(coloring.colors, key)
  color
}

fn members(coloring: Coloring, color: Int) -> List(Key) {
  set.to_list(class_members(coloring, color))
}

/// Give `keys` (one blank node per side) one fresh colour of their own.
fn individualize(
  coloring: Coloring,
  keys: List(Key),
) -> #(Coloring, List(Key)) {
  let fresh = coloring.next_color
  let coloring =
    list.fold(keys, coloring, fn(coloring, key) {
      move(coloring, key, color_of(coloring, key), fresh)
    })
  #(Coloring(..coloring, next_color: fresh + 1), spread(coloring, keys))
}

/// The colour of the smallest class with more than one member on the first
/// side (ties broken by the smaller colour), if any.
fn ambiguous_class(coloring: Coloring) -> Result(Int, Nil) {
  coloring.sizes
  |> dict.to_list
  |> list.filter(fn(entry) { entry.1.0 > 1 })
  |> list.sort(fn(a, b) {
    case int.compare(a.1.0, b.1.0) {
      order.Eq -> int.compare(a.0, b.0)
      other -> other
    }
  })
  |> list.first
  |> result.map(fn(entry) { entry.0 })
}

// Unambiguous, prefix-free encoding of statements. Every term starts with a
// tag character and strings are length-prefixed. A statement is encoded once
// into a template of text chunks and blank node slots; refinement only fills
// the slots in ("s" for the blank node being described, "c<colour>;" for any
// other blank node).

type Chunk {
  Text(String)
  Slot(String)
}

fn quad_template(quad: statement.Quad) -> List(Chunk) {
  let statement.Quad(subject, predicate, object, graph_name) = quad
  []
  |> encode_subject(subject, _)
  |> encode_named(predicate, _)
  |> encode_object(object, _)
  |> encode_graph_name(graph_name, _)
  |> compact_chunks([])
}

/// Reverse a reversed chunk list, merging adjacent text chunks.
fn compact_chunks(reversed: List(Chunk), acc: List(Chunk)) -> List(Chunk) {
  case reversed, acc {
    [], _ -> acc
    [Text(a), ..rest], [Text(b), ..acc] ->
      compact_chunks(rest, [Text(a <> b), ..acc])
    [chunk, ..rest], _ -> compact_chunks(rest, [chunk, ..acc])
  }
}

fn fill_template(template: List(Chunk), label: fn(String) -> String) -> String {
  template
  |> list.map(fn(chunk) {
    case chunk {
      Text(text) -> text
      Slot(id) -> label(id)
    }
  })
  |> string.concat
}

fn encode_subject(subject: term.Subject, acc: List(Chunk)) -> List(Chunk) {
  case subject {
    term.SubjectNamed(node) -> encode_named(node, acc)
    term.SubjectBlank(term.BlankNode(id)) -> [Slot(id), Text("B"), ..acc]
    term.SubjectTriple(triple) -> encode_triple_term(triple, acc)
  }
}

fn encode_object(object: term.Object, acc: List(Chunk)) -> List(Chunk) {
  case object {
    term.ObjectNamed(node) -> encode_named(node, acc)
    term.ObjectBlank(term.BlankNode(id)) -> [Slot(id), Text("B"), ..acc]
    term.ObjectLiteral(literal) -> [Text(encode_literal(literal)), ..acc]
    term.ObjectTriple(triple) -> encode_triple_term(triple, acc)
  }
}

fn encode_triple_term(
  triple: term.TripleTerm,
  acc: List(Chunk),
) -> List(Chunk) {
  let term.TripleTerm(subject, predicate, object) = triple
  [Text("("), ..acc]
  |> encode_subject(subject, _)
  |> encode_named(predicate, _)
  |> encode_object(object, _)
  |> fn(acc) { [Text(")"), ..acc] }
}

fn encode_graph_name(
  graph_name: term.GraphName,
  acc: List(Chunk),
) -> List(Chunk) {
  case graph_name {
    term.DefaultGraph -> [Text("G"), ..acc]
    term.NamedGraph(node) -> encode_named(node, acc)
    term.BlankGraph(term.BlankNode(id)) -> [Slot(id), Text("B"), ..acc]
  }
}

fn encode_named(node: term.NamedNode, acc: List(Chunk)) -> List(Chunk) {
  let term.NamedNode(iri) = node
  [Text("I" <> encode_string(iri)), ..acc]
}

fn encode_literal(literal: term.Literal) -> String {
  case literal {
    term.SimpleLiteral(value) -> "S" <> encode_string(value)
    term.LanguageTaggedLiteral(value, term.LanguageTag(tag)) ->
      "L" <> encode_string(value) <> encode_string(tag)
    term.DirectionalLanguageTaggedLiteral(value, term.LanguageTag(tag), dir) ->
      "D"
      <> encode_string(value)
      <> encode_string(tag)
      <> case dir {
        term.LeftToRight -> "l"
        term.RightToLeft -> "r"
      }
    term.TypedLiteral(value, term.NamedNode(datatype)) ->
      "T" <> encode_string(value) <> encode_string(datatype)
  }
}

fn encode_string(value: String) -> String {
  int.to_string(string.byte_size(value)) <> ":" <> value
}

// Blank nodes in every position, including nested triple terms ---------------

fn quad_has_blank(quad: statement.Quad) -> Bool {
  quad_blank_ids(quad) != []
}

fn quad_blank_ids(quad: statement.Quad) -> List(String) {
  let statement.Quad(subject, _predicate, object, graph_name) = quad
  let acc = case graph_name {
    term.BlankGraph(term.BlankNode(id)) -> [id]
    _ -> []
  }
  subject_blank_ids(subject, object_blank_ids(object, acc))
}

fn subject_blank_ids(subject: term.Subject, acc: List(String)) -> List(String) {
  case subject {
    term.SubjectNamed(_) -> acc
    term.SubjectBlank(term.BlankNode(id)) -> [id, ..acc]
    term.SubjectTriple(triple) -> triple_term_blank_ids(triple, acc)
  }
}

fn object_blank_ids(object: term.Object, acc: List(String)) -> List(String) {
  case object {
    term.ObjectNamed(_) | term.ObjectLiteral(_) -> acc
    term.ObjectBlank(term.BlankNode(id)) -> [id, ..acc]
    term.ObjectTriple(triple) -> triple_term_blank_ids(triple, acc)
  }
}

fn triple_term_blank_ids(
  triple: term.TripleTerm,
  acc: List(String),
) -> List(String) {
  let term.TripleTerm(subject, _predicate, object) = triple
  subject_blank_ids(subject, object_blank_ids(object, acc))
}

fn remap_quad(
  quad: statement.Quad,
  rename: fn(String) -> String,
) -> statement.Quad {
  let statement.Quad(subject, predicate, object, graph_name) = quad
  let graph_name = case graph_name {
    term.BlankGraph(term.BlankNode(id)) ->
      term.BlankGraph(term.BlankNode(rename(id)))
    _ -> graph_name
  }
  statement.Quad(
    subject: remap_subject(subject, rename),
    predicate: predicate,
    object: remap_object(object, rename),
    graph: graph_name,
  )
}

fn remap_subject(
  subject: term.Subject,
  rename: fn(String) -> String,
) -> term.Subject {
  case subject {
    term.SubjectNamed(_) -> subject
    term.SubjectBlank(term.BlankNode(id)) ->
      term.SubjectBlank(term.BlankNode(rename(id)))
    term.SubjectTriple(triple) ->
      term.SubjectTriple(remap_triple_term(triple, rename))
  }
}

fn remap_object(
  object: term.Object,
  rename: fn(String) -> String,
) -> term.Object {
  case object {
    term.ObjectNamed(_) | term.ObjectLiteral(_) -> object
    term.ObjectBlank(term.BlankNode(id)) ->
      term.ObjectBlank(term.BlankNode(rename(id)))
    term.ObjectTriple(triple) ->
      term.ObjectTriple(remap_triple_term(triple, rename))
  }
}

fn remap_triple_term(
  triple: term.TripleTerm,
  rename: fn(String) -> String,
) -> term.TripleTerm {
  let term.TripleTerm(subject, predicate, object) = triple
  term.TripleTerm(
    subject: remap_subject(subject, rename),
    predicate: predicate,
    object: remap_object(object, rename),
  )
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

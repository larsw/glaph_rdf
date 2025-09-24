import gleam/list
import glaph_rdf/graph
import glaph_rdf/statement
import glaph_rdf/term

pub type Dataset {
  Dataset(quads: List(statement.Quad))
}

pub fn new() -> Dataset {
  Dataset(quads: [])
}

pub fn from_list(quads: List(statement.Quad)) -> Dataset {
  Dataset(quads: dedupe(quads))
}

pub fn quads(dataset: Dataset) -> List(statement.Quad) {
  dataset.quads
}

pub fn quad_count(dataset: Dataset) -> Int {
  list.length(dataset.quads)
}

pub fn contains_quad(dataset: Dataset, quad: statement.Quad) -> Bool {
  list.any(dataset.quads, fn(existing) { existing == quad })
}

pub fn contains_triple(
  dataset: Dataset,
  triple: statement.Triple,
  graph_name: term.GraphName,
) -> Bool {
  contains_quad(dataset, statement.quad(triple, graph_name))
}

pub fn add_quad(dataset: Dataset, quad: statement.Quad) -> Dataset {
  case contains_quad(dataset, quad) {
    True -> dataset
    False -> Dataset(quads: [quad, ..dataset.quads])
  }
}

pub fn add_triple(dataset: Dataset, triple: statement.Triple) -> Dataset {
  add_quad(dataset, statement.quad(triple, term.DefaultGraph))
}

pub fn remove_quad(dataset: Dataset, quad: statement.Quad) -> Dataset {
  Dataset(quads: list.filter(dataset.quads, fn(existing) { existing != quad }))
}

pub fn remove_graph(dataset: Dataset, name: term.GraphName) -> Dataset {
  Dataset(quads: list.filter(dataset.quads, fn(quad) { quad.graph != name }))
}

pub fn default_graph(dataset: Dataset) -> graph.Graph {
  graph(dataset, term.DefaultGraph)
}

pub fn graph(dataset: Dataset, name: term.GraphName) -> graph.Graph {
  dataset.quads
  |> list.filter(fn(quad) { quad.graph == name })
  |> list.map(statement.triple_from_quad)
  |> graph.from_list
}

pub fn merge(into dataset: Dataset, from other: Dataset) -> Dataset {
  list.fold(other.quads, dataset, fn(acc, quad) { add_quad(acc, quad) })
}

pub fn replace_graph(
  dataset: Dataset,
  name: term.GraphName,
  new_graph: graph.Graph,
) -> Dataset {
  let stripped = remove_graph(dataset, name)

  list.fold(
    graph.triples(new_graph),
    stripped,
    fn(acc, triple) {
      add_quad(acc, statement.quad(triple, name))
    },
  )
}

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

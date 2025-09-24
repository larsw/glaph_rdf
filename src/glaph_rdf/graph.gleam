import gleam/list
import glaph_rdf/statement

pub type Graph {
  Graph(triples: List(statement.Triple))
}

pub fn new() -> Graph {
  Graph(triples: [])
}

pub fn from_list(triples: List(statement.Triple)) -> Graph {
  Graph(triples: dedupe(triples))
}

pub fn triples(graph: Graph) -> List(statement.Triple) {
  graph.triples
}

pub fn size(graph: Graph) -> Int {
  list.length(graph.triples)
}

pub fn contains(graph: Graph, triple: statement.Triple) -> Bool {
  list.any(graph.triples, fn(existing) { existing == triple })
}

pub fn add(graph: Graph, triple: statement.Triple) -> Graph {
  case contains(graph, triple) {
    True -> graph
    False -> Graph(triples: [triple, ..graph.triples])
  }
}

pub fn remove(graph: Graph, triple: statement.Triple) -> Graph {
  Graph(triples: list.filter(graph.triples, fn(existing) { existing != triple }))
}

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

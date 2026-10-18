//// Regression tests for bulk graph/dataset construction.
////
//// `graph.from_list`, `graph.merge`, `dataset.from_list`, `dataset.merge`,
//// `dataset.replace_graph` and `dataset.graph_names` used to deduplicate with
//// a list scan per item, which made building a graph of n triples O(n²).
//// With 20_000 items that is ~2x10^8 deep comparisons (tens of seconds per
//// call on the BEAM). They now dedupe with a set in O(n log n), so each bulk
//// call below must finish within `budget_ms`.

import glaph_rdf/dataset
import glaph_rdf/graph
import glaph_rdf/statement
import glaph_rdf/term
import gleam/float
import gleam/int
import gleam/list
import gleeunit/should

const big = 20_000

/// Generous wall-clock budget for one bulk call on 20_000+ items. The set
/// based implementation needs a few tens of milliseconds; the old list scan
/// needed tens of seconds.
const budget_ms = 3000.0

@target(erlang)
@external(erlang, "erlang", "monotonic_time")
fn erlang_monotonic_time(unit: Int) -> Int

@target(javascript)
@external(javascript, "node:process", "uptime")
fn uptime_seconds() -> Float

@target(erlang)
fn now_ms() -> Float {
  // A positive integer time unit means "parts per second".
  int.to_float(erlang_monotonic_time(1000))
}

@target(javascript)
fn now_ms() -> Float {
  uptime_seconds() *. 1000.0
}

/// Run `work` and fail the test if it takes longer than `budget_ms`.
fn within_budget(work: fn() -> a) -> a {
  let start = now_ms()
  let result = work()
  let elapsed = now_ms() -. start
  case elapsed <=. budget_ms {
    True -> Nil
    False ->
      panic as {
        "bulk operation took "
        <> int.to_string(float.round(elapsed))
        <> "ms, budget is "
        <> int.to_string(float.round(budget_ms))
        <> "ms (quadratic dedupe?)"
      }
  }
  result
}

fn triple(i: Int) -> statement.Triple {
  statement.Triple(
    subject: term.SubjectNamed(term.NamedNode(
      "http://example.org/s/" <> int.to_string(i),
    )),
    predicate: term.NamedNode("http://example.org/p"),
    object: term.ObjectLiteral(term.SimpleLiteral(int.to_string(i))),
  )
}

fn quad(i: Int, graph_index: Int) -> statement.Quad {
  let graph_name = case graph_index {
    0 -> term.DefaultGraph
    n ->
      term.NamedGraph(term.NamedNode(
        "http://example.org/g/" <> int.to_string(n),
      ))
  }
  statement.quad(triple(i), graph_name)
}

/// Inclusive integer range `[from, to]`.
fn ints(from: Int, to: Int) -> List(Int) {
  ints_loop(to, from, [])
}

fn ints_loop(current: Int, from: Int, acc: List(Int)) -> List(Int) {
  case current < from {
    True -> acc
    False -> ints_loop(current - 1, from, [current, ..acc])
  }
}

fn triples(from: Int, to: Int) -> List(statement.Triple) {
  ints(from, to) |> list.map(triple)
}

fn quads(from: Int, to: Int, graph_index: Int) -> List(statement.Quad) {
  ints(from, to) |> list.map(quad(_, graph_index))
}

// --- Speed / size --------------------------------------------------------

pub fn graph_from_list_large_test() {
  // 20_000 distinct triples followed by 10_000 duplicates of them.
  let input = list.append(triples(1, big), triples(1, big / 2))
  let g = within_budget(fn() { graph.from_list(input) })

  graph.size(g) |> should.equal(big)
  graph.contains(g, triple(big)) |> should.be_true
  graph.triples(g) |> list.first |> should.equal(Ok(triple(1)))
}

pub fn graph_merge_large_test() {
  let a = graph.from_list(triples(1, big))
  let b = graph.from_list(triples(big / 2, big + big / 2))

  within_budget(fn() { graph.merge(into: a, from: b) })
  |> graph.size
  |> should.equal(big + big / 2)
}

pub fn dataset_from_list_large_test() {
  // The same triple in two different graphs is two different quads.
  let input =
    list.flatten([
      quads(1, big, 0),
      quads(1, big / 2, 1),
      quads(1, big / 2, 0),
      quads(1, big / 4, 1),
    ])
  let d = within_budget(fn() { dataset.from_list(input) })

  dataset.quad_count(d) |> should.equal(big + big / 2)
  dataset.quads(d) |> list.first |> should.equal(Ok(quad(1, 0)))
}

pub fn dataset_merge_large_test() {
  let a = dataset.from_list(quads(1, big, 0))
  let b = dataset.from_list(list.append(quads(1, big, 0), quads(1, big, 1)))

  within_budget(fn() { dataset.merge(into: a, from: b) })
  |> dataset.quad_count
  |> should.equal(big * 2)
}

pub fn dataset_replace_graph_large_test() {
  let g = graph.from_list(triples(1, big))

  within_budget(fn() {
    dataset.new()
    |> dataset.replace_graph(term.DefaultGraph, g)
    |> dataset.replace_graph(term.NamedGraph(term.NamedNode("http://e/g")), g)
  })
  |> dataset.quad_count
  |> should.equal(big * 2)
}

pub fn dataset_graph_names_large_test() {
  // 20_000 quads, each in its own named graph, plus repeats.
  let input =
    ints(1, big)
    |> list.flat_map(fn(i) { [quad(1, i), quad(2, i)] })
  let d = within_budget(fn() { dataset.from_list(input) })

  within_budget(fn() { dataset.graph_names(d) })
  |> list.length
  |> should.equal(big)
}

// --- Semantics unchanged -------------------------------------------------

fn small_triples() -> List(statement.Triple) {
  [triple(3), triple(1), triple(3), triple(2), triple(1), triple(4)]
}

fn small_quads() -> List(statement.Quad) {
  [
    quad(1, 0),
    quad(1, 1),
    quad(2, 0),
    quad(1, 0),
    quad(3, 2),
    quad(1, 1),
    quad(2, 2),
  ]
}

pub fn graph_from_list_keeps_first_occurrence_in_order_test() {
  graph.from_list(small_triples())
  |> graph.triples
  |> should.equal([triple(3), triple(1), triple(2), triple(4)])
}

pub fn graph_from_list_matches_folding_add_test() {
  // Folding `add` prepends, so it yields the same set in reverse order.
  let folded = list.fold(small_triples(), graph.new(), graph.add)

  graph.from_list(small_triples())
  |> graph.triples
  |> should.equal(list.reverse(graph.triples(folded)))
}

pub fn graph_merge_matches_folding_add_test() {
  let base = graph.from_list([triple(1), triple(5), triple(2)])
  let other = graph.from_list(small_triples())
  let folded = list.fold(graph.triples(other), base, graph.add)

  graph.merge(into: base, from: other) |> should.equal(folded)
}

pub fn dataset_from_list_matches_folding_add_quad_test() {
  let folded = list.fold(small_quads(), dataset.new(), dataset.add_quad)
  let built = dataset.from_list(small_quads())

  dataset.quads(built)
  |> should.equal([quad(1, 0), quad(1, 1), quad(2, 0), quad(3, 2), quad(2, 2)])
  dataset.quads(built) |> should.equal(list.reverse(dataset.quads(folded)))
}

pub fn dataset_merge_matches_folding_add_quad_test() {
  let base = dataset.from_list([quad(2, 0), quad(9, 1)])
  let other = dataset.from_list(small_quads())
  let folded = list.fold(dataset.quads(other), base, dataset.add_quad)

  dataset.merge(into: base, from: other) |> should.equal(folded)
}

pub fn dataset_replace_graph_matches_folding_add_quad_test() {
  let name = term.NamedGraph(term.NamedNode("http://example.org/g/1"))
  let base = dataset.from_list(small_quads())
  let new_graph = graph.from_list([triple(7), triple(1), triple(8)])
  let folded =
    list.fold(
      graph.triples(new_graph),
      dataset.remove_graph(base, name),
      fn(acc, t) { dataset.add_quad(acc, statement.quad(t, name)) },
    )

  dataset.replace_graph(base, name, new_graph) |> should.equal(folded)
}

pub fn dataset_graph_names_order_test() {
  dataset.from_list(small_quads())
  |> dataset.graph_names
  |> should.equal([
    term.NamedGraph(term.NamedNode("http://example.org/g/1")),
    term.NamedGraph(term.NamedNode("http://example.org/g/2")),
  ])
}

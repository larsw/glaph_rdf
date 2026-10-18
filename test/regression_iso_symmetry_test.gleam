//// Regression tests for the running time of graph and dataset isomorphism
//// when the inputs contain symmetric parts that colour refinement already
//// grouped (structural twins, identical components) next to a difference
//// that refinement cannot see. The search used to try every bijection of the
//// symmetric part before failing (m! branches for m twins), so these
//// non-isomorphic inputs effectively hung. Every test runs on both Erlang
//// and JavaScript.

import glaph_rdf/dataset
import glaph_rdf/graph
import glaph_rdf/serializers/nquads
import glaph_rdf/serializers/ntriples
import gleam/int
import gleam/list
import gleam/string
import gleeunit/should

fn nt(text: String) -> graph.Graph {
  let assert Ok(doc) = ntriples.parse(text)
  doc.graph
}

fn iso_both_ways(a: String, b: String) -> Bool {
  let forward = graph.isomorphic(nt(a), nt(b))
  let backward = graph.isomorphic(nt(b), nt(a))
  should.equal(forward, backward)
  forward
}

fn range(n: Int) -> List(Int) {
  int.range(from: n - 1, to: -1, with: [], run: fn(acc, i) { [i, ..acc] })
}

fn label(prefix: String, i: Int) -> String {
  "_:" <> prefix <> int.to_string(i)
}

/// A directed cycle of `length` blank nodes, labelled from `start`.
fn cycle(prefix: String, start: Int, length: Int) -> String {
  range(length)
  |> list.map(fn(i) {
    label(prefix, start + i)
    <> " <http://e/next> "
    <> label(prefix, start + { i + 1 } % length)
    <> " .\n"
  })
  |> string.concat
}

/// `m` interchangeable blank nodes `_:t<i> a <Thing>`.
fn twins(prefix: String, m: Int) -> String {
  range(m)
  |> list.map(fn(i) {
    label(prefix <> "t", i)
    <> " <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://e/Thing> .\n"
  })
  |> string.concat
}

/// `m` identical two-node components.
fn pairs(prefix: String, m: Int) -> String {
  range(m)
  |> list.map(fn(i) {
    label(prefix <> "t", i)
    <> " <http://e/name> "
    <> label(prefix <> "u", i)
    <> " .\n"
    <> label(prefix <> "u", i)
    <> " <http://e/v> \"x\" .\n"
  })
  |> string.concat
}

/// One blank hub linking the `m` twins and, through a shared blank node,
/// every one of the 16 cycle nodes, so everything is a single component and
/// refinement still cannot tell the cycle nodes apart.
fn hub(prefix: String, m: Int) -> String {
  let hub = "_:" <> prefix <> "h"
  let shared = "_:" <> prefix <> "k"
  string.concat(
    list.map(range(m), fn(i) {
      hub <> " <http://e/has> " <> label(prefix <> "t", i) <> " .\n"
    }),
  )
  <> hub
  <> " <http://e/c> "
  <> shared
  <> " .\n"
  <> string.concat(
    list.map(range(16), fn(i) {
      label(prefix, i) <> " <http://e/in> " <> shared <> " .\n"
    }),
  )
}

fn one_long_cycle(prefix: String) -> String {
  cycle(prefix, 0, 16)
}

fn two_short_cycles(prefix: String) -> String {
  cycle(prefix, 0, 8) <> cycle(prefix, 8, 8)
}

pub fn twins_beside_hidden_difference_test() {
  let m = 10
  iso_both_ways(
    twins("a", m) <> one_long_cycle("a"),
    twins("b", m) <> two_short_cycles("b"),
  )
  |> should.be_false
  iso_both_ways(
    twins("a", m) <> two_short_cycles("a"),
    two_short_cycles("b") <> twins("b", m),
  )
  |> should.be_true
}

pub fn identical_components_beside_hidden_difference_test() {
  let m = 10
  iso_both_ways(
    pairs("a", m) <> one_long_cycle("a"),
    pairs("b", m) <> two_short_cycles("b"),
  )
  |> should.be_false
  iso_both_ways(
    pairs("a", m) <> one_long_cycle("a"),
    one_long_cycle("b") <> pairs("b", m),
  )
  |> should.be_true
}

pub fn twins_in_same_component_as_hidden_difference_test() {
  let m = 10
  iso_both_ways(
    twins("a", m) <> one_long_cycle("a") <> hub("a", m),
    twins("b", m) <> two_short_cycles("b") <> hub("b", m),
  )
  |> should.be_false
  iso_both_ways(
    twins("a", m) <> two_short_cycles("a") <> hub("a", m),
    hub("b", m) <> two_short_cycles("b") <> twins("b", m),
  )
  |> should.be_true
}

pub fn dataset_twins_beside_hidden_difference_test() {
  // The same shapes with the cycles inside a blank-named graph.
  let in_graph = fn(text: String, graph: String) {
    text
    |> string.split(" .\n")
    |> list.filter(fn(line) { line != "" })
    |> list.map(fn(line) { line <> " " <> graph <> " .\n" })
    |> string.concat
  }
  let nq = fn(text: String) {
    let assert Ok(doc) = nquads.parse(text)
    doc.dataset
  }
  let m = 10
  let a = twins("a", m) <> in_graph(one_long_cycle("a"), "_:ga")
  let b = twins("b", m) <> in_graph(two_short_cycles("b"), "_:gb")
  dataset.isomorphic(nq(a), nq(b)) |> should.be_false
  dataset.isomorphic(nq(b), nq(a)) |> should.be_false
  let c = in_graph(one_long_cycle("c"), "_:gc") <> twins("c", m)
  dataset.isomorphic(nq(a), nq(c)) |> should.be_true
}

// Strongly regular graphs srg(16, 6, 2, 2): refinement cannot split them.

fn all_pairs(n: Int) -> List(#(Int, Int)) {
  list.flat_map(range(n), fn(a) {
    list.filter_map(range(n), fn(b) {
      case a < b {
        True -> Ok(#(a, b))
        False -> Error(Nil)
      }
    })
  })
}

fn shrikhande() -> List(#(Int, Int)) {
  list.filter(all_pairs(16), fn(edge) {
    let dx = { edge.1 / 4 - edge.0 / 4 + 4 } % 4
    let dy = { edge.1 % 4 - edge.0 % 4 + 4 } % 4
    case dx, dy {
      0, 1 | 0, 3 | 1, 0 | 3, 0 | 1, 1 | 3, 3 -> True
      _, _ -> False
    }
  })
}

fn rook() -> List(#(Int, Int)) {
  list.filter(all_pairs(16), fn(edge) {
    edge.0 / 4 == edge.1 / 4 || edge.0 % 4 == edge.1 % 4
  })
}

/// Undirected edges of several 16-node graphs side by side, written in both
/// directions. `relabel` scrambles the node numbers.
fn copies(
  prefix: String,
  graphs: List(List(#(Int, Int))),
  relabel: fn(Int) -> Int,
) -> String {
  graphs
  |> list.index_map(fn(edges, index) {
    list.flat_map(edges, fn(edge) {
      let a = relabel(edge.0 + 16 * index)
      let b = relabel(edge.1 + 16 * index)
      [
        label(prefix, a) <> " <http://e/p> " <> label(prefix, b) <> " .\n",
        label(prefix, b) <> " <http://e/p> " <> label(prefix, a) <> " .\n",
      ]
    })
  })
  |> list.flatten
  |> string.concat
}

pub fn several_copies_of_strongly_regular_graphs_test() {
  let s = shrikhande()
  let r = rook()
  let same = fn(i) { i }
  let scramble = fn(i) { { i * 7 + 3 } % 48 }
  iso_both_ways(copies("a", [s, s, s], same), copies("b", [r, s, s], same))
  |> should.be_false
  iso_both_ways(copies("a", [s, s, s], same), copies("b", [s, s, r], same))
  |> should.be_false
  iso_both_ways(copies("a", [s, r, s], same), copies("b", [s, s, r], scramble))
  |> should.be_true
}

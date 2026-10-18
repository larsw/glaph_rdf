//// Regression tests for graph and dataset isomorphism with RDF 1.2 triple
//// terms, blank nodes nested inside triple terms, blank nodes shared across
//// named graphs, blank graph names and graphs that colour refinement alone
//// cannot tell apart. Every test runs on both Erlang and JavaScript.

import glaph_rdf/dataset
import glaph_rdf/graph
import glaph_rdf/serializers/nquads
import glaph_rdf/serializers/ntriples
import glaph_rdf/term
import gleam/int
import gleam/list
import gleam/string
import gleeunit/should

// Helpers ---------------------------------------------------------------------

fn nt(text: String) -> graph.Graph {
  let assert Ok(doc) = ntriples.parse(text)
  doc.graph
}

fn nq(text: String) -> dataset.Dataset {
  let assert Ok(doc) = nquads.parse(text)
  doc.dataset
}

fn quoted_statement(literal: String) -> String {
  "<http://ex.org/s> <http://ex.org/p> <<( <http://ex.org/a> <http://ex.org/b> "
  <> literal
  <> " )>> .\n"
}

fn iso(a: String, b: String) -> Bool {
  graph.isomorphic(nt(a), nt(b))
}

fn iso_both_ways(a: String, b: String) -> Bool {
  let forward = iso(a, b)
  let backward = iso(b, a)
  should.equal(forward, backward)
  forward
}

fn dataset_iso(a: String, b: String) -> Bool {
  let forward = dataset.isomorphic(nq(a), nq(b))
  let backward = dataset.isomorphic(nq(b), nq(a))
  should.equal(forward, backward)
  forward
}

// Triple terms that differ only inside the triple term ------------------------
//
// The sort key used to give every triple term the same key "T:QUOTED", so two
// statements differing only inside a triple term sorted as equal, the stable
// sort kept arrival order and the final equality check failed.

pub fn triple_terms_differing_in_direction_order_independent_test() {
  let a = quoted_statement("\"x\"@en--ltr")
  let b = quoted_statement("\"x\"@en--rtl")
  iso(a <> b, b <> a) |> should.be_true
  iso(b <> a, a <> b) |> should.be_true
  iso(a <> b, a <> b) |> should.be_true
}

pub fn triple_terms_differing_in_language_order_independent_test() {
  let a = quoted_statement("\"x\"@en")
  let b = quoted_statement("\"x\"@fr")
  iso(a <> b, b <> a) |> should.be_true
  iso(b <> a, a <> b) |> should.be_true
}

pub fn triple_terms_differing_in_literal_kind_order_independent_test() {
  let statements = [
    quoted_statement("\"x\""),
    quoted_statement("\"x\"@en"),
    quoted_statement("\"x\"@en--ltr"),
    quoted_statement("\"x\"^^<http://ex.org/dt>"),
    quoted_statement("\"x\"^^<http://ex.org/dt2>"),
    quoted_statement("<http://ex.org/x>"),
  ]
  let forward = string.concat(statements)
  let backward = string.concat(list.reverse(statements))
  iso(forward, backward) |> should.be_true
}

pub fn triple_terms_with_different_content_are_not_isomorphic_test() {
  iso_both_ways(
    quoted_statement("\"x\"@en--ltr"),
    quoted_statement("\"x\"@en--rtl"),
  )
  |> should.be_false
  iso_both_ways(quoted_statement("\"x\"@en"), quoted_statement("\"x\"@fr"))
  |> should.be_false
  iso_both_ways(quoted_statement("\"x\"@en"), quoted_statement("\"x\"@en--ltr"))
  |> should.be_false
}

pub fn subject_triple_terms_order_independent_test() {
  let a =
    "<<( <http://ex.org/a> <http://ex.org/b> \"x\"@en--ltr )>> <http://ex.org/p> <http://ex.org/o> .\n"
  let b =
    "<<( <http://ex.org/a> <http://ex.org/b> \"x\"@en--rtl )>> <http://ex.org/p> <http://ex.org/o> .\n"
  iso(a <> b, b <> a) |> should.be_true
}

pub fn nested_triple_terms_order_independent_test() {
  let nested = fn(literal) {
    "<http://ex.org/s> <http://ex.org/p> <<( <http://ex.org/a> <http://ex.org/b> <<( <http://ex.org/c> <http://ex.org/d> "
    <> literal
    <> " )>> )>> .\n"
  }
  let a = nested("\"x\"@en--ltr")
  let b = nested("\"x\"@en--rtl")
  let c = nested("\"x\"@fr")
  iso(a <> b <> c, c <> b <> a) |> should.be_true
  iso(b <> c <> a, a <> c <> b) |> should.be_true
  iso_both_ways(a <> b, a <> c) |> should.be_false
}

// Blank nodes inside triple terms ---------------------------------------------

pub fn blank_nodes_inside_triple_terms_renamed_are_isomorphic_test() {
  let a =
    "_:a <http://ex.org/p> <<( _:b <http://ex.org/q> _:a )>> .\n"
    <> "_:b <http://ex.org/r> \"1\" .\n"
  let b =
    "_:y <http://ex.org/r> \"1\" .\n"
    <> "_:x <http://ex.org/p> <<( _:y <http://ex.org/q> _:x )>> .\n"
  iso_both_ways(a, b) |> should.be_true
}

pub fn blank_node_only_inside_triple_term_renamed_is_isomorphic_test() {
  let a =
    "<http://ex.org/s> <http://ex.org/p> <<( _:a <http://ex.org/q> \"v\" )>> .\n"
  let b =
    "<http://ex.org/s> <http://ex.org/p> <<( _:zz <http://ex.org/q> \"v\" )>> .\n"
  iso_both_ways(a, b) |> should.be_true
}

pub fn blank_node_inside_triple_term_label_collision_is_not_isomorphic_test() {
  // Blank nodes inside triple terms used to be left unmapped, so `_:x` was
  // relabelled to `_:b0` and collided with the untouched `_:b0` inside the
  // triple term: two distinct blank nodes became one.
  let a =
    "_:x <http://ex.org/p> <<( _:b0 <http://ex.org/q> <http://ex.org/o> )>> .\n"
  let b =
    "_:b0 <http://ex.org/p> <<( _:b0 <http://ex.org/q> <http://ex.org/o> )>> .\n"
  iso_both_ways(a, b) |> should.be_false
}

pub fn blank_nodes_inside_triple_terms_different_structure_test() {
  let same =
    "_:a <http://ex.org/p> <<( _:a <http://ex.org/q> <http://ex.org/o> )>> .\n"
  let different =
    "_:a <http://ex.org/p> <<( _:b <http://ex.org/q> <http://ex.org/o> )>> .\n"
  iso_both_ways(same, different) |> should.be_false

  let a =
    "_:a <http://ex.org/p> <<( _:b <http://ex.org/q> _:c )>> .\n"
    <> "_:b <http://ex.org/r> \"1\" .\n"
    <> "_:c <http://ex.org/r> \"2\" .\n"
  let b =
    "_:a <http://ex.org/p> <<( _:c <http://ex.org/q> _:b )>> .\n"
    <> "_:b <http://ex.org/r> \"1\" .\n"
    <> "_:c <http://ex.org/r> \"2\" .\n"
  iso_both_ways(a, b) |> should.be_false
}

pub fn blank_nodes_in_nested_triple_terms_test() {
  let a =
    "_:a <http://ex.org/p> <<( _:b <http://ex.org/q> <<( _:a <http://ex.org/r> _:b )>> )>> .\n"
  let renamed =
    "_:n <http://ex.org/p> <<( _:m <http://ex.org/q> <<( _:n <http://ex.org/r> _:m )>> )>> .\n"
  let swapped =
    "_:a <http://ex.org/p> <<( _:b <http://ex.org/q> <<( _:b <http://ex.org/r> _:a )>> )>> .\n"
  iso_both_ways(a, renamed) |> should.be_true
  iso_both_ways(a, swapped) |> should.be_false
}

// Blank node labels must not influence the result -----------------------------

pub fn blank_node_labels_do_not_leak_into_signatures_test() {
  // Signatures used to embed the labels of neighbouring blank nodes, so the
  // canonical labels depended on the input labels and these isomorphic graphs
  // (two disjoint edges) were reported as different.
  let a = "_:a <http://ex.org/p> _:b .\n_:c <http://ex.org/p> _:d .\n"
  let b = "_:a <http://ex.org/p> _:d .\n_:c <http://ex.org/p> _:b .\n"
  iso_both_ways(a, b) |> should.be_true
}

fn cycle(labels: List(String)) -> String {
  let assert [first, ..] = labels
  list.zip(labels, list.append(list.drop(labels, 1), [first]))
  |> list.map(fn(pair) {
    "_:" <> pair.0 <> " <http://ex.org/p> _:" <> pair.1 <> " .\n"
  })
  |> string.concat
}

pub fn regular_graphs_need_backtracking_test() {
  // Every blank node has one incoming and one outgoing edge in all of these,
  // so colour refinement alone cannot separate them.
  let hexagon = cycle(["a", "b", "c", "d", "e", "f"])
  let hexagon_renamed = cycle(["u", "w", "z", "v", "x", "y"])
  let two_triangles = cycle(["a", "b", "c"]) <> cycle(["d", "e", "f"])
  iso_both_ways(hexagon, hexagon_renamed) |> should.be_true
  iso_both_ways(hexagon, two_triangles) |> should.be_false
  iso_both_ways(two_triangles, cycle(["x", "y", "z"]) <> cycle(["p", "q", "r"]))
  |> should.be_true
}

pub fn many_symmetric_blank_nodes_test() {
  let statements = fn(prefix) {
    range(1, 40)
    |> list.map(fn(i) {
      "_:"
      <> prefix
      <> int.to_string(i)
      <> " <http://ex.org/p> <http://ex.org/o> .\n"
    })
  }
  let a = string.concat(statements("a"))
  let b = string.concat(list.reverse(statements("z")))
  iso_both_ways(a, b) |> should.be_true
  iso_both_ways(a, b <> "_:extra <http://ex.org/p> <http://ex.org/o> .\n")
  |> should.be_false
}

pub fn long_blank_node_chain_test() {
  let chain = fn(prefix, n) {
    range(1, n)
    |> list.map(fn(i) {
      "_:"
      <> prefix
      <> int.to_string(i)
      <> " <http://ex.org/next> _:"
      <> prefix
      <> int.to_string(i + 1)
      <> " .\n"
    })
  }
  let a = string.concat(chain("a", 150))
  let b = string.concat(list.reverse(chain("q", 150)))
  iso_both_ways(a, b) |> should.be_true
  iso_both_ways(
    a,
    string.concat(chain("q", 149)) <> "_:q150 <http://ex.org/next> _:q1 .\n",
  )
  |> should.be_false
}

// Canonicalisation ------------------------------------------------------------

pub fn canonicalize_relabels_blank_nodes_inside_triple_terms_test() {
  let text =
    "_:x <http://ex.org/p> <<( _:b0 <http://ex.org/q> <http://ex.org/o> )>> .\n"
  let original = nt(text)
  let canonical = graph.canonicalize(original)
  graph.isomorphic(canonical, original) |> should.be_true
  graph.isomorphic(
    canonical,
    nt(
      "_:b0 <http://ex.org/p> <<( _:b0 <http://ex.org/q> <http://ex.org/o> )>> .\n",
    ),
  )
  |> should.be_false
}

pub fn canonicalize_is_label_independent_test() {
  let a =
    "_:a <http://ex.org/p> <<( _:b <http://ex.org/q> _:a )>> .\n"
    <> "_:b <http://ex.org/r> _:c .\n"
    <> "_:c <http://ex.org/r> \"x\"@en--rtl .\n"
  let b =
    "_:k <http://ex.org/r> \"x\"@en--rtl .\n"
    <> "_:j <http://ex.org/r> _:k .\n"
    <> "_:i <http://ex.org/p> <<( _:j <http://ex.org/q> _:i )>> .\n"
  let canonical_a = graph.canonicalize(nt(a))
  let canonical_b = graph.canonicalize(nt(b))
  list.sort(graph.triples(canonical_a), fn(x, y) {
    string.compare(string.inspect(x), string.inspect(y))
  })
  |> should.equal(
    list.sort(graph.triples(canonical_b), fn(x, y) {
      string.compare(string.inspect(x), string.inspect(y))
    }),
  )
}

pub fn dataset_canonicalize_keeps_shared_blank_nodes_test() {
  // Quads used to be canonicalised one at a time, so `_:b` became `_:b1` in
  // the first quad and `_:b0` in the second.
  let original =
    nq(
      "_:a <http://ex.org/p> _:b <http://ex.org/g1> .\n"
      <> "_:b <http://ex.org/q> <http://ex.org/o> <http://ex.org/g2> .\n",
    )
  let canonical = dataset.canonicalize(original)
  dataset.isomorphic(canonical, original) |> should.be_true
  let assert [first, second] = dataset.quads(canonical)
  let assert term.ObjectBlank(term.BlankNode(object_label)) = first.object
  let assert term.SubjectBlank(term.BlankNode(subject_label)) = second.subject
  object_label |> should.equal(subject_label)
  let assert term.SubjectBlank(term.BlankNode(other_label)) = first.subject
  { other_label != object_label } |> should.be_true
}

// Datasets --------------------------------------------------------------------

fn quoted_quad(literal: String, graph_name: String) -> String {
  "<http://ex.org/s> <http://ex.org/p> <<( <http://ex.org/a> <http://ex.org/b> "
  <> literal
  <> " )>> "
  <> graph_name
  <> " .\n"
}

pub fn dataset_triple_terms_order_independent_test() {
  let a = quoted_quad("\"x\"@en--ltr", "<http://ex.org/g1>")
  let b = quoted_quad("\"x\"@en--rtl", "<http://ex.org/g1>")
  let c = quoted_quad("\"x\"@en", "<http://ex.org/g2>")
  let d = quoted_quad("\"x\"@fr", "<http://ex.org/g2>")
  let e = quoted_quad("\"x\"@en--ltr", "")
  let f = quoted_quad("\"x\"@en--rtl", "")
  dataset_iso(a <> b <> c <> d <> e <> f, f <> d <> b <> e <> c <> a)
  |> should.be_true
  dataset_iso(a <> c, b <> c) |> should.be_false
  dataset_iso(a <> c, quoted_quad("\"x\"@en--ltr", "<http://ex.org/g2>") <> c)
  |> should.be_false
}

pub fn dataset_blank_nodes_in_triple_terms_across_graphs_test() {
  let a =
    "_:s <http://ex.org/p> <<( _:t <http://ex.org/q> \"1\" )>> <http://ex.org/g1> .\n"
    <> "_:t <http://ex.org/r> _:s <http://ex.org/g2> .\n"
  let renamed =
    "_:m <http://ex.org/r> _:n <http://ex.org/g2> .\n"
    <> "_:n <http://ex.org/p> <<( _:m <http://ex.org/q> \"1\" )>> <http://ex.org/g1> .\n"
  let reversed =
    "_:s <http://ex.org/p> <<( _:t <http://ex.org/q> \"1\" )>> <http://ex.org/g1> .\n"
    <> "_:s <http://ex.org/r> _:t <http://ex.org/g2> .\n"
  dataset_iso(a, renamed) |> should.be_true
  dataset_iso(a, reversed) |> should.be_false
}

pub fn dataset_blank_nodes_shared_across_graphs_test() {
  // Named graphs used to be compared independently, each with its own blank
  // node mapping, which ignores blank nodes shared between graphs.
  let shared =
    "_:a <http://ex.org/p> <http://ex.org/o> <http://ex.org/g1> .\n"
    <> "_:a <http://ex.org/p> <http://ex.org/o> <http://ex.org/g2> .\n"
  let separate =
    "_:a <http://ex.org/p> <http://ex.org/o> <http://ex.org/g1> .\n"
    <> "_:b <http://ex.org/p> <http://ex.org/o> <http://ex.org/g2> .\n"
  dataset_iso(shared, separate) |> should.be_false
}

pub fn dataset_blank_graph_names_test() {
  // Every canonical blank graph name used to be resolved to the first blank
  // graph name of each dataset.
  let a =
    "<http://ex.org/s> <http://ex.org/p> \"1\" _:x .\n"
    <> "<http://ex.org/s> <http://ex.org/p> \"2\" _:y .\n"
  let b =
    "<http://ex.org/s> <http://ex.org/p> \"2\" _:u .\n"
    <> "<http://ex.org/s> <http://ex.org/p> \"1\" _:v .\n"
  let merged =
    "<http://ex.org/s> <http://ex.org/p> \"1\" _:u .\n"
    <> "<http://ex.org/s> <http://ex.org/p> \"2\" _:u .\n"
  dataset_iso(a, b) |> should.be_true
  dataset_iso(a, merged) |> should.be_false
}

pub fn dataset_blank_graph_name_shared_with_subject_test() {
  let same = "_:g <http://ex.org/p> <http://ex.org/o> _:g .\n"
  let renamed = "_:h <http://ex.org/p> <http://ex.org/o> _:h .\n"
  let different = "_:a <http://ex.org/p> <http://ex.org/o> _:b .\n"
  dataset_iso(same, renamed) |> should.be_true
  dataset_iso(same, different) |> should.be_false
}

fn range(from: Int, to: Int) -> List(Int) {
  range_loop(to, from, [])
}

fn range_loop(current: Int, from: Int, acc: List(Int)) -> List(Int) {
  case current < from {
    True -> acc
    False -> range_loop(current - 1, from, [current, ..acc])
  }
}

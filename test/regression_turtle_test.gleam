//// Regression tests for the Turtle and TriG serializers.
////
//// - Compacting IRIs to prefixed names when the namespace contains non-ASCII
////   characters. `string.drop_start` on the JavaScript target mixed UTF-8 byte
////   and UTF-16 unit offsets, so `http://example.org/café/Person` with the
////   namespace `http://example.org/café/` serialized as `ex:erson`.
//// - Relative IRI resolution against a base IRI with an upper-case scheme.

import glaph_rdf/dataset
import glaph_rdf/graph
import glaph_rdf/serializers/trig
import glaph_rdf/serializers/turtle
import glaph_rdf/statement
import glaph_rdf/term
import gleam/dict
import gleam/option.{None}
import gleam/string
import gleeunit/should

const cafe_ns = "http://example.org/café/"

const cjk_ns = "http://example.org/日本語/"

fn cafe_triple() -> statement.Triple {
  statement.Triple(
    subject: term.SubjectNamed(term.unsafe_named_node(cafe_ns <> "alice")),
    predicate: term.unsafe_named_node(cafe_ns <> "knows"),
    object: term.ObjectNamed(term.unsafe_named_node(cafe_ns <> "Person")),
  )
}

fn cjk_triple() -> statement.Triple {
  statement.Triple(
    subject: term.SubjectNamed(term.unsafe_named_node(cjk_ns <> "alice")),
    predicate: term.unsafe_named_node(cjk_ns <> "knows"),
    object: term.ObjectNamed(term.unsafe_named_node(cjk_ns <> "Person")),
  )
}

pub fn turtle_non_ascii_namespace_prefixed_name_test() {
  let prefixes = dict.from_list([#("ex", cafe_ns)])
  let output =
    turtle.serialize_graph(graph.from_list([cafe_triple()]), None, prefixes)

  should.be_true(string.contains(output, "ex:alice ex:knows ex:Person ."))
  should.be_false(string.contains(output, "ex:erson"))
}

pub fn turtle_cjk_namespace_prefixed_name_test() {
  let prefixes = dict.from_list([#("ja", cjk_ns)])
  let output =
    turtle.serialize_graph(graph.from_list([cjk_triple()]), None, prefixes)

  should.be_true(string.contains(output, "ja:alice ja:knows ja:Person ."))
}

pub fn turtle_non_ascii_namespace_round_trip_test() {
  let original = graph.from_list([cafe_triple(), cjk_triple()])
  let prefixes = dict.from_list([#("ex", cafe_ns), #("ja", cjk_ns)])
  let output = turtle.serialize_graph(original, None, prefixes)

  let assert Ok(parsed) = turtle.parse_graph(output)
  should.equal(graph.size(parsed), 2)
  should.be_true(graph.contains(parsed, cafe_triple()))
  should.be_true(graph.contains(parsed, cjk_triple()))
}

pub fn trig_non_ascii_namespace_prefixed_name_test() {
  let prefixes = dict.from_list([#("ex", cafe_ns)])
  let data =
    dataset.new()
    |> dataset.add_triple(cafe_triple())
  let output = trig.serialize_dataset(data, None, prefixes)

  should.be_true(string.contains(output, "ex:alice ex:knows ex:Person ."))
  should.be_false(string.contains(output, "ex:erson"))
}

pub fn trig_non_ascii_namespace_named_graph_name_test() {
  let prefixes = dict.from_list([#("ex", cafe_ns), #("ja", cjk_ns)])
  let graph_name = term.NamedGraph(term.unsafe_named_node(cjk_ns <> "graph"))
  let triple = cafe_triple()
  let quad =
    statement.Quad(
      subject: triple.subject,
      predicate: triple.predicate,
      object: triple.object,
      graph: graph_name,
    )
  let output = trig.serialize_dataset(dataset.from_list([quad]), None, prefixes)

  should.be_true(string.contains(output, "ja:graph {"))
  should.be_true(string.contains(output, "ex:alice ex:knows ex:Person ."))
}

pub fn trig_non_ascii_namespace_round_trip_test() {
  let prefixes = dict.from_list([#("ex", cafe_ns), #("ja", cjk_ns)])
  let data =
    dataset.new()
    |> dataset.add_triple(cafe_triple())
    |> dataset.add_triple(cjk_triple())
  let output = trig.serialize_dataset(data, None, prefixes)

  let assert Ok(parsed) = trig.parse_dataset(output)
  should.equal(dataset.quad_count(parsed), 2)
  should.be_true(dataset.contains_triple(
    parsed,
    cafe_triple(),
    term.DefaultGraph,
  ))
  should.be_true(dataset.contains_triple(
    parsed,
    cjk_triple(),
    term.DefaultGraph,
  ))
}

// Relative IRI resolution against a base with an upper-case scheme. URI
// schemes are case-insensitive (RFC 3986 section 3.1), and the resolution
// algorithm (section 5.2) copies the base scheme unchanged. gleam/uri used to
// resolve `<c/d>` to `HTTP://Example.org/d` on JavaScript (it parsed `c` as a
// scheme) and lowercased the scheme on Erlang.
pub fn turtle_relative_iri_upper_case_base_scheme_test() {
  let text =
    "@base <HTTP://Example.org/a/> .
<b> <http://example.org/p> <c/d> ."

  let assert Ok(parsed) = turtle.parse_graph(text)
  let assert [triple] = graph.triples(parsed)
  let assert term.SubjectNamed(term.NamedNode(subject_iri)) = triple.subject
  let assert term.ObjectNamed(term.NamedNode(object_iri)) = triple.object

  should.equal(subject_iri, "HTTP://Example.org/a/b")
  should.equal(object_iri, "HTTP://Example.org/a/c/d")
}

fn resolve(reference: String) -> String {
  let text = "@base <http://a/b/c/d;p?q> .
<http://example.org/s> <http://example.org/p> <" <> reference <> "> ."
  let assert Ok(parsed) = turtle.parse_graph(text)
  let assert [triple] = graph.triples(parsed)
  let assert term.ObjectNamed(term.NamedNode(iri)) = triple.object
  iri
}

// Reference resolution examples from RFC 3986 section 5.4.
pub fn turtle_rfc3986_normal_examples_test() {
  should.equal(resolve("g"), "http://a/b/c/g")
  should.equal(resolve("./g"), "http://a/b/c/g")
  should.equal(resolve("g/"), "http://a/b/c/g/")
  should.equal(resolve("/g"), "http://a/g")
  should.equal(resolve("//g"), "http://g")
  should.equal(resolve("?y"), "http://a/b/c/d;p?y")
  should.equal(resolve("g?y"), "http://a/b/c/g?y")
  should.equal(resolve("#s"), "http://a/b/c/d;p?q#s")
  should.equal(resolve("g#s"), "http://a/b/c/g#s")
  should.equal(resolve("g?y#s"), "http://a/b/c/g?y#s")
  should.equal(resolve(";x"), "http://a/b/c/;x")
  should.equal(resolve("g;x?y#s"), "http://a/b/c/g;x?y#s")
  should.equal(resolve(""), "http://a/b/c/d;p?q")
  should.equal(resolve("."), "http://a/b/c/")
  should.equal(resolve("./"), "http://a/b/c/")
  should.equal(resolve(".."), "http://a/b/")
  should.equal(resolve("../"), "http://a/b/")
  should.equal(resolve("../g"), "http://a/b/g")
  should.equal(resolve("../.."), "http://a/")
  should.equal(resolve("../../g"), "http://a/g")
}

pub fn turtle_rfc3986_abnormal_examples_test() {
  should.equal(resolve("../../../g"), "http://a/g")
  should.equal(resolve("/./g"), "http://a/g")
  should.equal(resolve("/../g"), "http://a/g")
  should.equal(resolve("g."), "http://a/b/c/g.")
  should.equal(resolve(".g"), "http://a/b/c/.g")
  should.equal(resolve("g.."), "http://a/b/c/g..")
  should.equal(resolve("..g"), "http://a/b/c/..g")
  should.equal(resolve("./../g"), "http://a/b/g")
  should.equal(resolve("./g/."), "http://a/b/c/g/")
  should.equal(resolve("g/./h"), "http://a/b/c/g/h")
  should.equal(resolve("g/../h"), "http://a/b/c/h")
  should.equal(resolve("g;x=1/./y"), "http://a/b/c/g;x=1/y")
  should.equal(resolve("g;x=1/../y"), "http://a/b/c/y")
  should.equal(resolve("g?y/./x"), "http://a/b/c/g?y/./x")
  should.equal(resolve("g#s/../x"), "http://a/b/c/g#s/../x")
  // A colon after a `/` or `#` does not start a scheme.
  should.equal(resolve("g/h:i"), "http://a/b/c/g/h:i")
  should.equal(resolve("#a:b"), "http://a/b/c/d;p?q#a:b")
}

pub fn turtle_absolute_iri_ignores_base_test() {
  should.equal(resolve("urn:isbn:0451450523"), "urn:isbn:0451450523")
  should.equal(resolve("HTTPS://Other.example/x"), "HTTPS://Other.example/x")
}

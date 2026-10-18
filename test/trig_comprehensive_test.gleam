import glaph_rdf/dataset
import glaph_rdf/graph
import glaph_rdf/serializers/trig
import glaph_rdf/statement
import glaph_rdf/term
import gleam/dict
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

// Helper function to check if a string contains another string
fn contains(haystack: String, needle: String) -> Bool {
  string.contains(haystack, needle)
}

// Comprehensive TriG Serialization Tests

pub fn serialize_multiple_named_graphs_test() {
  // Create two different triples
  let alice_triple =
    statement.Triple(
      term.SubjectNamed(term.unsafe_named_node("http://example.org/alice")),
      term.unsafe_named_node("http://xmlns.com/foaf/0.1/name"),
      term.ObjectLiteral(term.simple_literal("Alice")),
    )

  let bob_triple =
    statement.Triple(
      term.SubjectNamed(term.unsafe_named_node("http://example.org/bob")),
      term.unsafe_named_node("http://xmlns.com/foaf/0.1/name"),
      term.ObjectLiteral(term.simple_literal("Bob")),
    )

  // Create graphs
  let graph1 =
    graph.new()
    |> graph.add(alice_triple)

  let graph2 =
    graph.new()
    |> graph.add(bob_triple)

  // Create named graphs
  let graph_name1 =
    term.NamedGraph(term.unsafe_named_node("http://example.org/persons"))
  let graph_name2 =
    term.NamedGraph(term.unsafe_named_node("http://example.org/people"))

  let dataset_multi =
    dataset.new()
    |> dataset.replace_graph(graph_name1, graph1)
    |> dataset.replace_graph(graph_name2, graph2)

  let doc =
    trig.TrigDocument(base: None, prefixes: dict.new(), dataset: dataset_multi)

  let result = trig.serialize(doc)

  // Verify both graphs are serialized
  should.be_true(contains(result, "<http://example.org/persons>"))
  should.be_true(contains(result, "<http://example.org/people>"))
  should.be_true(contains(result, "Alice"))
  should.be_true(contains(result, "Bob"))
  should.be_true(contains(result, "{"))
  should.be_true(contains(result, "}"))
}

pub fn serialize_blank_node_graph_test() {
  let triple =
    statement.Triple(
      term.SubjectNamed(term.unsafe_named_node("http://example.org/alice")),
      term.unsafe_named_node("http://xmlns.com/foaf/0.1/name"),
      term.ObjectLiteral(term.simple_literal("Alice")),
    )

  let graph_with_triple =
    graph.new()
    |> graph.add(triple)

  let blank_graph_name = term.BlankGraph(term.unsafe_blank_node("metadata"))
  let dataset_with_blank =
    dataset.new()
    |> dataset.replace_graph(blank_graph_name, graph_with_triple)

  let doc =
    trig.TrigDocument(
      base: None,
      prefixes: dict.new(),
      dataset: dataset_with_blank,
    )

  let result = trig.serialize(doc)

  // Verify blank node graph syntax
  should.be_true(contains(result, "_:metadata"))
  should.be_true(contains(result, "{"))
  should.be_true(contains(result, "}"))
  should.be_true(contains(result, "Alice"))
}

pub fn serialize_mixed_default_and_named_graphs_test() {
  let default_triple =
    statement.Triple(
      term.SubjectNamed(term.unsafe_named_node("http://example.org/default")),
      term.unsafe_named_node("http://example.org/property"),
      term.ObjectLiteral(term.simple_literal("default value")),
    )

  let named_triple =
    statement.Triple(
      term.SubjectNamed(term.unsafe_named_node("http://example.org/named")),
      term.unsafe_named_node("http://example.org/property"),
      term.ObjectLiteral(term.simple_literal("named value")),
    )

  let default_graph =
    graph.new()
    |> graph.add(default_triple)

  let named_graph =
    graph.new()
    |> graph.add(named_triple)

  let graph_name =
    term.NamedGraph(term.unsafe_named_node("http://example.org/named-graph"))

  let mixed_dataset =
    dataset.new()
    |> dataset.replace_graph(term.DefaultGraph, default_graph)
    |> dataset.replace_graph(graph_name, named_graph)

  let doc =
    trig.TrigDocument(base: None, prefixes: dict.new(), dataset: mixed_dataset)

  let result = trig.serialize(doc)

  // Verify both default and named graph content
  should.be_true(contains(result, "default value"))
  should.be_true(contains(result, "named value"))
  should.be_true(contains(result, "<http://example.org/named-graph>"))
  should.be_true(contains(result, "{"))
  should.be_true(contains(result, "}"))
}

pub fn serialize_complex_with_prefixes_test() {
  let prefixes =
    dict.new()
    |> dict.insert("ex", "http://example.org/")
    |> dict.insert("foaf", "http://xmlns.com/foaf/0.1/")
    |> dict.insert("rdf", "http://www.w3.org/1999/02/22-rdf-syntax-ns#")

  let alice_triple =
    statement.Triple(
      term.SubjectNamed(term.unsafe_named_node("http://example.org/alice")),
      term.unsafe_named_node("http://www.w3.org/1999/02/22-rdf-syntax-ns#type"),
      term.ObjectNamed(term.unsafe_named_node(
        "http://xmlns.com/foaf/0.1/Person",
      )),
    )

  let name_triple =
    statement.Triple(
      term.SubjectNamed(term.unsafe_named_node("http://example.org/alice")),
      term.unsafe_named_node("http://xmlns.com/foaf/0.1/name"),
      term.ObjectLiteral(term.simple_literal("Alice")),
    )

  let person_graph =
    graph.new()
    |> graph.add(alice_triple)
    |> graph.add(name_triple)

  let graph_name =
    term.NamedGraph(term.unsafe_named_node("http://example.org/people"))

  let complex_dataset =
    dataset.new()
    |> dataset.replace_graph(graph_name, person_graph)

  let doc =
    trig.TrigDocument(
      base: Some("http://example.org/base/"),
      prefixes: prefixes,
      dataset: complex_dataset,
    )

  let result = trig.serialize(doc)

  // Verify prefixes are used
  should.be_true(contains(result, "@base"))
  should.be_true(contains(result, "@prefix ex:"))
  should.be_true(contains(result, "@prefix foaf:"))
  should.be_true(contains(result, "@prefix rdf:"))
  should.be_true(contains(result, "ex:alice"))
  should.be_true(contains(result, "foaf:name"))
  should.be_true(contains(result, "foaf:Person"))
  should.be_true(contains(result, "a "))
  // rdf:type shorthand
}

pub fn serialize_dataset_with_literals_test() {
  let string_triple =
    statement.Triple(
      term.SubjectNamed(term.unsafe_named_node("http://example.org/alice")),
      term.unsafe_named_node("http://xmlns.com/foaf/0.1/name"),
      term.ObjectLiteral(term.simple_literal("Alice")),
    )

  let age_triple =
    statement.Triple(
      term.SubjectNamed(term.unsafe_named_node("http://example.org/alice")),
      term.unsafe_named_node("http://xmlns.com/foaf/0.1/age"),
      term.ObjectLiteral(term.typed_literal(
        "30",
        term.unsafe_named_node("http://www.w3.org/2001/XMLSchema#integer"),
      )),
    )

  let label_triple =
    statement.Triple(
      term.SubjectNamed(term.unsafe_named_node("http://example.org/alice")),
      term.unsafe_named_node("http://www.w3.org/2000/01/rdf-schema#label"),
      term.ObjectLiteral(term.language_literal("Alice", term.LanguageTag("en"))),
    )

  let literal_graph =
    graph.new()
    |> graph.add(string_triple)
    |> graph.add(age_triple)
    |> graph.add(label_triple)

  let graph_name =
    term.NamedGraph(term.unsafe_named_node("http://example.org/literals"))

  let literal_dataset =
    dataset.new()
    |> dataset.replace_graph(graph_name, literal_graph)

  let doc =
    trig.TrigDocument(
      base: None,
      prefixes: dict.new(),
      dataset: literal_dataset,
    )

  let result = trig.serialize(doc)

  // Verify different literal types
  should.be_true(contains(result, "\"Alice\""))
  // Simple literal
  should.be_true(contains(result, "30"))
  // Integer literal (no quotes)
  should.be_true(contains(result, "\"Alice\"@en"))
  // Language-tagged literal
}

pub fn parse_simple_turtle_as_trig_test() {
  let simple_turtle =
    "
  <http://example.org/alice> <http://xmlns.com/foaf/0.1/name> \"Alice\" .
  <http://example.org/bob> <http://xmlns.com/foaf/0.1/name> \"Bob\" .
  "

  case trig.parse(simple_turtle) {
    Ok(doc) -> {
      let default_graph = dataset.default_graph(doc.dataset)
      should.equal(graph.size(default_graph), 2)
    }
    Error(_) -> should.fail()
  }
}

pub fn parse_with_base_and_prefixes_test() {
  let turtle_with_prefixes =
    "
  @base <http://example.org/> .
  @prefix foaf: <http://xmlns.com/foaf/0.1/> .
  <alice> foaf:name \"Alice\" .
  "

  case trig.parse(turtle_with_prefixes) {
    Ok(doc) -> {
      should.equal(doc.base, Some("http://example.org/"))
      should.be_true(dict.has_key(doc.prefixes, "foaf"))
      let default_graph = dataset.default_graph(doc.dataset)
      should.equal(graph.size(default_graph), 1)
    }
    Error(_) -> should.fail()
  }
}

// Test string escaping in TriG output

pub fn serialize_string_escaping_test() {
  let escape_triple =
    statement.Triple(
      term.SubjectNamed(term.unsafe_named_node("http://example.org/text")),
      term.unsafe_named_node("http://example.org/content"),
      term.ObjectLiteral(term.simple_literal(
        "Line 1\nLine 2\t\"Quoted\"\\Backslash",
      )),
    )

  let escape_graph =
    graph.new()
    |> graph.add(escape_triple)

  let escape_dataset =
    dataset.new()
    |> dataset.replace_graph(term.DefaultGraph, escape_graph)

  let doc =
    trig.TrigDocument(base: None, prefixes: dict.new(), dataset: escape_dataset)

  let result = trig.serialize(doc)

  // Verify proper escaping
  should.be_true(contains(result, "\\n"))
  // Newline escaped
  should.be_true(contains(result, "\\t"))
  // Tab escaped
  should.be_true(contains(result, "\\\""))
  // Quote escaped
  should.be_true(contains(result, "\\\\"))
  // Backslash escaped
}

pub fn serialize_iri_escaping_test() {
  let escape_triple =
    statement.Triple(
      term.SubjectNamed(term.unsafe_named_node(
        "http://example.org/test>with>brackets",
      )),
      term.unsafe_named_node("http://example.org/predicate"),
      term.ObjectNamed(term.unsafe_named_node(
        "http://example.org/object>with>brackets",
      )),
    )

  let escape_graph =
    graph.new()
    |> graph.add(escape_triple)

  let escape_dataset =
    dataset.new()
    |> dataset.replace_graph(term.DefaultGraph, escape_graph)

  let doc =
    trig.TrigDocument(base: None, prefixes: dict.new(), dataset: escape_dataset)

  let result = trig.serialize(doc)

  // '>' cannot appear in an IRIREF, and Turtle/TriG have no "\\>" escape:
  // it is written as a UCHAR, as in N-Triples.
  should.be_true(contains(result, "\\u003E"))
  should.be_false(contains(result, "\\>"))
}

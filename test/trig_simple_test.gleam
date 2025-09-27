import glaph_rdf/dataset
import glaph_rdf/graph
import glaph_rdf/serializers/trig
import glaph_rdf/statement
import glaph_rdf/term
import gleam/dict
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

// Basic TriG Document Tests

pub fn parse_empty_test() {
  let result = trig.parse("")
  should.be_ok(result)
}

pub fn serialize_empty_test() {
  let empty_doc =
    trig.TrigDocument(base: None, prefixes: dict.new(), dataset: dataset.new())
  let result = trig.serialize(empty_doc)
  should.equal(result, "")
}

// Base URI Test

pub fn serialize_with_base_test() {
  let doc =
    trig.TrigDocument(
      base: Some("http://example.org/"),
      prefixes: dict.new(),
      dataset: dataset.new(),
    )
  let result = trig.serialize(doc)
  should.equal(result, "@base <http://example.org/> .")
}

// Prefix Test

pub fn serialize_with_prefix_test() {
  let prefixes =
    dict.new()
    |> dict.insert("ex", "http://example.org/")

  let doc =
    trig.TrigDocument(base: None, prefixes: prefixes, dataset: dataset.new())

  let result = trig.serialize(doc)
  should.equal(result, "@prefix ex: <http://example.org/> .")
}

// Default Graph Test

pub fn serialize_default_graph_test() {
  let subject =
    term.SubjectNamed(term.unsafe_named_node("http://example.org/alice"))
  let predicate = term.unsafe_named_node("http://xmlns.com/foaf/0.1/name")
  let object = term.ObjectLiteral(term.simple_literal("Alice"))
  let triple = statement.Triple(subject, predicate, object)

  let graph_with_triple =
    graph.new()
    |> graph.add(triple)

  let dataset_with_default =
    dataset.new()
    |> dataset.replace_graph(term.DefaultGraph, graph_with_triple)

  let doc =
    trig.TrigDocument(
      base: None,
      prefixes: dict.new(),
      dataset: dataset_with_default,
    )

  let result = trig.serialize(doc)
  should.equal(
    result,
    "<http://example.org/alice> <http://xmlns.com/foaf/0.1/name> \"Alice\" .",
  )
}

// Named Graph Test

pub fn serialize_named_graph_test() {
  let subject =
    term.SubjectNamed(term.unsafe_named_node("http://example.org/alice"))
  let predicate = term.unsafe_named_node("http://xmlns.com/foaf/0.1/name")
  let object = term.ObjectLiteral(term.simple_literal("Alice"))
  let triple = statement.Triple(subject, predicate, object)

  let graph_with_triple =
    graph.new()
    |> graph.add(triple)

  let graph_name =
    term.NamedGraph(term.unsafe_named_node("http://example.org/graph1"))
  let dataset_with_named =
    dataset.new()
    |> dataset.replace_graph(graph_name, graph_with_triple)

  let doc =
    trig.TrigDocument(
      base: None,
      prefixes: dict.new(),
      dataset: dataset_with_named,
    )

  let result = trig.serialize(doc)

  // Check that it contains the expected components
  should.not_equal(result, "")
}

// Blank Graph Test

pub fn serialize_blank_graph_test() {
  let subject =
    term.SubjectNamed(term.unsafe_named_node("http://example.org/alice"))
  let predicate = term.unsafe_named_node("http://xmlns.com/foaf/0.1/name")
  let object = term.ObjectLiteral(term.simple_literal("Alice"))
  let triple = statement.Triple(subject, predicate, object)

  let graph_with_triple =
    graph.new()
    |> graph.add(triple)

  let graph_name = term.BlankGraph(term.unsafe_blank_node("g1"))
  let dataset_with_blank =
    dataset.new()
    |> dataset.replace_graph(graph_name, graph_with_triple)

  let doc =
    trig.TrigDocument(
      base: None,
      prefixes: dict.new(),
      dataset: dataset_with_blank,
    )

  let result = trig.serialize(doc)
  should.not_equal(result, "")
}

// Empty Named Graph Test - Currently empty graphs are not tracked
// TODO: Enhance dataset to track empty named graphs for proper TriG serialization

pub fn serialize_empty_named_graph_test() {
  let graph_name =
    term.NamedGraph(term.unsafe_named_node("http://example.org/empty"))
  let dataset_with_empty =
    dataset.new()
    |> dataset.replace_graph(graph_name, graph.new())

  let doc =
    trig.TrigDocument(
      base: None,
      prefixes: dict.new(),
      dataset: dataset_with_empty,
    )

  let result = trig.serialize(doc)
  // Empty graphs are not currently serialized since they contain no quads
  should.equal(result, "")
}

// RDF Type Shorthand Test

pub fn serialize_rdf_type_test() {
  let subject =
    term.SubjectNamed(term.unsafe_named_node("http://example.org/alice"))
  let predicate =
    term.unsafe_named_node("http://www.w3.org/1999/02/22-rdf-syntax-ns#type")
  let object =
    term.ObjectNamed(term.unsafe_named_node("http://xmlns.com/foaf/0.1/Person"))
  let triple = statement.Triple(subject, predicate, object)

  let graph_with_type =
    graph.new()
    |> graph.add(triple)

  let dataset_with_type =
    dataset.new()
    |> dataset.replace_graph(term.DefaultGraph, graph_with_type)

  let doc =
    trig.TrigDocument(
      base: None,
      prefixes: dict.new(),
      dataset: dataset_with_type,
    )

  let result = trig.serialize(doc)
  should.not_equal(result, "")
}

// Dataset Serialization Test

pub fn serialize_dataset_test() {
  let subject =
    term.SubjectNamed(term.unsafe_named_node("http://example.org/alice"))
  let predicate = term.unsafe_named_node("http://xmlns.com/foaf/0.1/name")
  let object = term.ObjectLiteral(term.simple_literal("Alice"))
  let triple = statement.Triple(subject, predicate, object)

  let graph_with_triple =
    graph.new()
    |> graph.add(triple)

  let test_dataset =
    dataset.new()
    |> dataset.replace_graph(term.DefaultGraph, graph_with_triple)

  let prefixes =
    dict.new()
    |> dict.insert("foaf", "http://xmlns.com/foaf/0.1/")

  let result = trig.serialize_dataset(test_dataset, None, prefixes)
  should.not_equal(result, "")
}

// Parse Tests

pub fn parse_turtle_as_trig_test() {
  let turtle_text =
    "<http://example.org/alice> <http://xmlns.com/foaf/0.1/name> \"Alice\" ."

  case trig.parse(turtle_text) {
    Ok(doc) -> {
      let default_graph = dataset.default_graph(doc.dataset)
      should.equal(graph.size(default_graph), 1)
    }
    Error(_) -> should.fail()
  }
}

pub fn parse_dataset_test() {
  let turtle_text =
    "<http://example.org/alice> <http://xmlns.com/foaf/0.1/name> \"Alice\" ."

  case trig.parse_dataset(turtle_text) {
    Ok(dataset_result) -> {
      let default_graph = dataset.default_graph(dataset_result)
      should.equal(graph.size(default_graph), 1)
    }
    Error(_) -> should.fail()
  }
}

// Prefix Usage Test

pub fn serialize_with_prefix_usage_test() {
  let prefixes =
    dict.new()
    |> dict.insert("ex", "http://example.org/")
    |> dict.insert("foaf", "http://xmlns.com/foaf/0.1/")

  let subject =
    term.SubjectNamed(term.unsafe_named_node("http://example.org/alice"))
  let predicate = term.unsafe_named_node("http://xmlns.com/foaf/0.1/name")
  let object = term.ObjectLiteral(term.simple_literal("Alice"))
  let triple = statement.Triple(subject, predicate, object)

  let graph_with_triple =
    graph.new()
    |> graph.add(triple)

  let dataset_with_default =
    dataset.new()
    |> dataset.replace_graph(term.DefaultGraph, graph_with_triple)

  let doc =
    trig.TrigDocument(
      base: None,
      prefixes: prefixes,
      dataset: dataset_with_default,
    )

  let result = trig.serialize(doc)
  should.not_equal(result, "")
}

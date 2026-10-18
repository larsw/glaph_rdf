import glaph_rdf/dataset
import glaph_rdf/graph
import glaph_rdf/serializers/trig
import glaph_rdf/serializers/turtle
import glaph_rdf/statement
import glaph_rdf/term
import gleam/dict
import gleam/list
import gleam/option.{None}
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

// Advanced RDF 1.2 Test Cases

// Test with blank nodes in triple terms
pub fn triple_term_with_blank_nodes_test() {
  let blank_triple =
    term.triple_term(
      term.SubjectBlank(term.unsafe_blank_node("person1")),
      term.unsafe_named_node("http://xmlns.com/foaf/0.1/knows"),
      term.ObjectBlank(term.unsafe_blank_node("person2")),
    )

  let confidence_statement =
    statement.Triple(
      term.SubjectTriple(blank_triple),
      term.unsafe_named_node("http://example.org/confidence"),
      term.ObjectLiteral(term.typed_literal(
        "0.8",
        term.unsafe_named_node("http://www.w3.org/2001/XMLSchema#decimal"),
      )),
    )

  let graph_with_blanks =
    graph.new()
    |> graph.add(confidence_statement)

  let turtle_doc =
    turtle.TurtleDocument(
      base: None,
      prefixes: dict.new(),
      graph: graph_with_blanks,
    )

  let result = turtle.serialize(turtle_doc)

  should.be_true(contains(result, "<<"))
  should.be_true(contains(result, "_:person1"))
  should.be_true(contains(result, "_:person2"))
  should.be_true(contains(result, "0.8"))
}

// Test with mixed literals in triple terms  
pub fn triple_term_with_mixed_literals_test() {
  // Triple with different literal types
  let typed_literal_triple =
    term.triple_term(
      term.SubjectNamed(term.unsafe_named_node("http://example.org/measurement")),
      term.unsafe_named_node("http://example.org/temperature"),
      term.ObjectLiteral(term.typed_literal(
        "23.5",
        term.unsafe_named_node("http://www.w3.org/2001/XMLSchema#decimal"),
      )),
    )

  // Language-tagged description of the measurement
  let description_statement =
    statement.Triple(
      term.SubjectTriple(typed_literal_triple),
      term.unsafe_named_node("http://www.w3.org/2000/01/rdf-schema#comment"),
      term.ObjectLiteral(term.language_literal(
        "Temperature measurement",
        term.LanguageTag("en"),
      )),
    )

  let graph_mixed =
    graph.new()
    |> graph.add(description_statement)

  let turtle_doc =
    turtle.TurtleDocument(base: None, prefixes: dict.new(), graph: graph_mixed)

  let result = turtle.serialize(turtle_doc)

  should.be_true(contains(result, "<<"))
  should.be_true(contains(result, "23.5"))
  should.be_true(contains(result, "\"Temperature measurement\"@en"))
}

// Test RDF type (rdf:type) in triple terms with shorthand
pub fn triple_term_with_rdf_type_test() {
  let type_triple =
    term.triple_term(
      term.SubjectNamed(term.unsafe_named_node("http://example.org/alice")),
      term.unsafe_named_node("http://www.w3.org/1999/02/22-rdf-syntax-ns#type"),
      term.ObjectNamed(term.unsafe_named_node(
        "http://xmlns.com/foaf/0.1/Person",
      )),
    )

  let classification_statement =
    statement.Triple(
      term.SubjectTriple(type_triple),
      term.unsafe_named_node("http://example.org/accuracy"),
      term.ObjectLiteral(term.simple_literal("verified")),
    )

  let graph_with_type =
    graph.new()
    |> graph.add(classification_statement)

  let turtle_doc =
    turtle.TurtleDocument(
      base: None,
      prefixes: dict.new(),
      graph: graph_with_type,
    )

  let result = turtle.serialize(turtle_doc)

  should.be_true(contains(result, "<<"))
  should.be_true(contains(result, "a "))
  // Should use 'a' shorthand
  should.be_true(contains(result, "\"verified\""))
}

// Test multiple assertions about the same base statement
pub fn multiple_assertions_same_statement_test() {
  let base_fact =
    term.triple_term(
      term.SubjectNamed(term.unsafe_named_node("http://example.org/paris")),
      term.unsafe_named_node("http://example.org/capitalOf"),
      term.ObjectNamed(term.unsafe_named_node("http://example.org/france")),
    )

  let source1_statement =
    statement.Triple(
      term.SubjectTriple(base_fact),
      term.unsafe_named_node("http://www.w3.org/ns/prov#wasAttributedTo"),
      term.ObjectNamed(term.unsafe_named_node("http://example.org/atlas2023")),
    )

  let confidence1_statement =
    statement.Triple(
      term.SubjectTriple(base_fact),
      term.unsafe_named_node("http://example.org/confidence"),
      term.ObjectLiteral(term.typed_literal(
        "1.0",
        term.unsafe_named_node("http://www.w3.org/2001/XMLSchema#decimal"),
      )),
    )

  let verified_statement =
    statement.Triple(
      term.SubjectTriple(base_fact),
      term.unsafe_named_node("http://example.org/verified"),
      term.ObjectLiteral(term.typed_literal(
        "true",
        term.unsafe_named_node("http://www.w3.org/2001/XMLSchema#boolean"),
      )),
    )

  let multi_assertion_graph =
    graph.new()
    |> graph.add(source1_statement)
    |> graph.add(confidence1_statement)
    |> graph.add(verified_statement)

  let turtle_doc =
    turtle.TurtleDocument(
      base: None,
      prefixes: dict.new(),
      graph: multi_assertion_graph,
    )

  let result = turtle.serialize(turtle_doc)

  // Should contain the base fact three times (once per assertion)
  let fact_count = count_occurrences(result, "http://example.org/paris")
  should.be_true(fact_count >= 3)
  should.be_true(contains(result, "http://example.org/atlas2023"))
  should.be_true(contains(result, "1.0"))
  should.be_true(contains(result, "true"))
}

// Test RDF-star in TriG with different graph contexts
pub fn rdf_star_across_multiple_graphs_test() {
  let base_triple =
    term.triple_term(
      term.SubjectNamed(term.unsafe_named_node("http://example.org/alice")),
      term.unsafe_named_node("http://xmlns.com/foaf/0.1/knows"),
      term.ObjectNamed(term.unsafe_named_node("http://example.org/bob")),
    )

  // Assertion in first graph
  let assertion1 =
    statement.Triple(
      term.SubjectTriple(base_triple),
      term.unsafe_named_node("http://example.org/confidence"),
      term.ObjectLiteral(term.simple_literal("high")),
    )

  // Assertion in second graph
  let assertion2 =
    statement.Triple(
      term.SubjectTriple(base_triple),
      term.unsafe_named_node("http://example.org/source"),
      term.ObjectLiteral(term.simple_literal("social_network")),
    )

  let graph1 =
    graph.new()
    |> graph.add(assertion1)

  let graph2 =
    graph.new()
    |> graph.add(assertion2)

  let graph_name1 =
    term.NamedGraph(term.unsafe_named_node("http://example.org/confidence_data"))
  let graph_name2 =
    term.NamedGraph(term.unsafe_named_node("http://example.org/source_data"))

  let multi_graph_dataset =
    dataset.new()
    |> dataset.replace_graph(graph_name1, graph1)
    |> dataset.replace_graph(graph_name2, graph2)

  let trig_doc =
    trig.TrigDocument(
      base: None,
      prefixes: dict.new(),
      dataset: multi_graph_dataset,
    )

  let result = trig.serialize(trig_doc)

  should.be_true(contains(result, "<http://example.org/confidence_data>"))
  should.be_true(contains(result, "<http://example.org/source_data>"))
  should.be_true(contains(result, "<<"))
  should.be_true(contains(result, ">>"))
  should.be_true(contains(result, "\"high\""))
  should.be_true(contains(result, "\"social_network\""))
}

// Test quotation of statements that themselves contain quoted triples
pub fn recursive_quotation_test() {
  // Base statement
  let base =
    term.triple_term(
      term.SubjectNamed(term.unsafe_named_node("http://example.org/doc1")),
      term.unsafe_named_node("http://purl.org/dc/terms/title"),
      term.ObjectLiteral(term.simple_literal("RDF Specification")),
    )

  // First level assertion
  let level1 =
    term.triple_term(
      term.SubjectTriple(base),
      term.unsafe_named_node("http://example.org/verifiedBy"),
      term.ObjectNamed(term.unsafe_named_node("http://example.org/w3c")),
    )

  // Second level assertion (assertion about an assertion)
  let level2 =
    term.triple_term(
      term.SubjectTriple(level1),
      term.unsafe_named_node("http://example.org/timestamp"),
      term.ObjectLiteral(term.typed_literal(
        "2023-12-01",
        term.unsafe_named_node("http://www.w3.org/2001/XMLSchema#date"),
      )),
    )

  // Third level assertion (assertion about assertion about assertion)
  let final_statement =
    statement.Triple(
      term.SubjectTriple(level2),
      term.unsafe_named_node("http://example.org/recorded"),
      term.ObjectLiteral(term.simple_literal("yes")),
    )

  let recursive_graph =
    graph.new()
    |> graph.add(final_statement)

  let turtle_doc =
    turtle.TurtleDocument(
      base: None,
      prefixes: dict.new(),
      graph: recursive_graph,
    )

  let result = turtle.serialize(turtle_doc)

  // Should have multiple levels of RDF 1.2 triple term nesting
  should.be_true(contains(result, "<<( <<( <<( "))
  should.equal(list.length(string.split(result, " )>>")), 4)
  should.be_true(contains(result, "RDF Specification"))
  should.be_true(contains(result, "2023-12-01"))
  should.be_true(contains(result, "\"yes\""))
}

// Test with prefixes applied to triple terms
pub fn triple_term_with_prefixes_test() {
  let prefixes =
    dict.new()
    |> dict.insert("ex", "http://example.org/")
    |> dict.insert("foaf", "http://xmlns.com/foaf/0.1/")
    |> dict.insert("dc", "http://purl.org/dc/terms/")

  let prefixed_triple =
    term.triple_term(
      term.SubjectNamed(term.unsafe_named_node("http://example.org/book1")),
      term.unsafe_named_node("http://purl.org/dc/terms/author"),
      term.ObjectNamed(term.unsafe_named_node("http://example.org/smith")),
    )

  let attribution_statement =
    statement.Triple(
      term.SubjectTriple(prefixed_triple),
      term.unsafe_named_node("http://example.org/catalogedBy"),
      term.ObjectNamed(term.unsafe_named_node("http://example.org/library")),
    )

  let prefixed_graph =
    graph.new()
    |> graph.add(attribution_statement)

  let turtle_doc =
    turtle.TurtleDocument(base: None, prefixes: prefixes, graph: prefixed_graph)

  let result = turtle.serialize(turtle_doc)

  // Should use prefixes inside quoted triples
  should.be_true(contains(result, "@prefix ex:"))
  should.be_true(contains(result, "@prefix dc:"))
  should.be_true(contains(result, "<<"))
  should.be_true(contains(result, "ex:book1"))
  should.be_true(contains(result, "dc:author"))
  should.be_true(contains(result, "ex:smith"))
}

// Test edge case: empty quoted triples (should not be possible in valid RDF-star)
// But we test the serialization of minimal valid triples
pub fn minimal_triple_term_test() {
  let minimal_triple =
    term.triple_term(
      term.SubjectNamed(term.unsafe_named_node("http://a.example/s")),
      term.unsafe_named_node("http://a.example/p"),
      term.ObjectNamed(term.unsafe_named_node("http://a.example/o")),
    )

  let minimal_statement =
    statement.Triple(
      term.SubjectTriple(minimal_triple),
      term.unsafe_named_node("http://a.example/meta"),
      term.ObjectLiteral(term.simple_literal("x")),
    )

  let minimal_graph =
    graph.new()
    |> graph.add(minimal_statement)

  let turtle_doc =
    turtle.TurtleDocument(
      base: None,
      prefixes: dict.new(),
      graph: minimal_graph,
    )

  let result = turtle.serialize(turtle_doc)

  should.be_true(contains(result, "<<"))
  should.be_true(contains(result, "http://a.example/s"))
  should.be_true(contains(result, "http://a.example/p"))
  should.be_true(contains(result, "http://a.example/o"))
  should.be_true(contains(result, ">>"))
  should.be_true(contains(result, "\"x\""))
}

// Test combining traditional RDF with RDF-star in the same graph
pub fn mixed_traditional_and_star_test() {
  // Traditional triple
  let traditional =
    statement.Triple(
      term.SubjectNamed(term.unsafe_named_node("http://example.org/alice")),
      term.unsafe_named_node("http://xmlns.com/foaf/0.1/name"),
      term.ObjectLiteral(term.simple_literal("Alice")),
    )

  // RDF-star triple (assertion about another statement)
  let quoted_triple =
    term.triple_term(
      term.SubjectNamed(term.unsafe_named_node("http://example.org/bob")),
      term.unsafe_named_node("http://xmlns.com/foaf/0.1/name"),
      term.ObjectLiteral(term.simple_literal("Bob")),
    )

  let star_statement =
    statement.Triple(
      term.SubjectTriple(quoted_triple),
      term.unsafe_named_node("http://example.org/confidence"),
      term.ObjectLiteral(term.typed_literal(
        "0.95",
        term.unsafe_named_node("http://www.w3.org/2001/XMLSchema#decimal"),
      )),
    )

  let combined_graph =
    graph.new()
    |> graph.add(traditional)
    |> graph.add(star_statement)

  let turtle_doc =
    turtle.TurtleDocument(
      base: None,
      prefixes: dict.new(),
      graph: combined_graph,
    )

  let result = turtle.serialize(turtle_doc)

  // Should contain both traditional and RDF-star syntax
  should.be_true(contains(result, "\"Alice\""))
  // Traditional
  should.be_true(contains(result, "<<"))
  // RDF-star
  should.be_true(contains(result, "\"Bob\""))
  // Inside quoted triple
  should.be_true(contains(result, "0.95"))
  // Assertion value
}

// Helper function to count occurrences
fn count_occurrences(text: String, pattern: String) -> Int {
  let original_len = string.length(text)
  let without_pattern = string.replace(text, pattern, "")
  let new_len = string.length(without_pattern)
  let pattern_len = string.length(pattern)
  case pattern_len {
    0 -> 0
    _ -> {
      let diff = original_len - new_len
      diff / pattern_len
    }
  }
}

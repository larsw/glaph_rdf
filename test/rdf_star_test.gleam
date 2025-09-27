import glaph_rdf/dataset
import glaph_rdf/graph
import glaph_rdf/serializers/trig
import glaph_rdf/serializers/turtle
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

// RDF-star / RDF 1.2 Triple Term Tests

pub fn create_simple_triple_term_test() {
  let triple_term =
    term.triple_term(
      term.SubjectNamed(term.unsafe_named_node("http://example.org/alice")),
      term.unsafe_named_node("http://xmlns.com/foaf/0.1/name"),
      term.ObjectLiteral(term.simple_literal("Alice")),
    )

  // Test the structure
  let term.TripleTerm(subject, predicate, object) = triple_term

  case subject {
    term.SubjectNamed(term.NamedNode(iri)) ->
      should.equal(iri, "http://example.org/alice")
    _ -> should.fail()
  }

  let term.NamedNode(pred_iri) = predicate
  should.equal(pred_iri, "http://xmlns.com/foaf/0.1/name")

  case object {
    term.ObjectLiteral(term.SimpleLiteral(value)) ->
      should.equal(value, "Alice")
    _ -> should.fail()
  }
}

pub fn create_unsafe_triple_term_test() {
  let triple_term =
    term.unsafe_triple_term(
      "http://example.org/alice",
      "http://xmlns.com/foaf/0.1/name",
      "http://example.org/alice_name",
    )

  let term.TripleTerm(subject, predicate, object) = triple_term

  case subject {
    term.SubjectNamed(term.NamedNode(iri)) ->
      should.equal(iri, "http://example.org/alice")
    _ -> should.fail()
  }
}

// Triple Terms as Subjects

pub fn serialize_triple_term_as_subject_turtle_test() {
  // Create a quoted triple term
  let quoted_triple =
    term.triple_term(
      term.SubjectNamed(term.unsafe_named_node("http://example.org/alice")),
      term.unsafe_named_node("http://xmlns.com/foaf/0.1/name"),
      term.ObjectLiteral(term.simple_literal("Alice")),
    )

  // Use the quoted triple as a subject in another statement
  let assertion_triple =
    statement.Triple(
      term.SubjectTriple(quoted_triple),
      term.unsafe_named_node("http://example.org/confidence"),
      term.ObjectLiteral(term.typed_literal(
        "0.95",
        term.unsafe_named_node("http://www.w3.org/2001/XMLSchema#decimal"),
      )),
    )

  let graph_with_assertion =
    graph.new()
    |> graph.add(assertion_triple)

  let turtle_doc =
    turtle.TurtleDocument(
      base: None,
      prefixes: dict.new(),
      graph: graph_with_assertion,
    )

  let result = turtle.serialize(turtle_doc)

  // Should contain the RDF-star syntax
  should.be_true(contains(result, "<<"))
  should.be_true(contains(result, ">>"))
  should.be_true(contains(result, "http://example.org/alice"))
  should.be_true(contains(result, "http://xmlns.com/foaf/0.1/name"))
  should.be_true(contains(result, "\"Alice\""))
  should.be_true(contains(result, "http://example.org/confidence"))
  should.be_true(contains(result, "0.95"))
}

// Triple Terms as Objects

pub fn serialize_triple_term_as_object_turtle_test() {
  // Create a quoted triple term
  let quoted_triple =
    term.triple_term(
      term.SubjectNamed(term.unsafe_named_node("http://example.org/bob")),
      term.unsafe_named_node("http://xmlns.com/foaf/0.1/age"),
      term.ObjectLiteral(term.typed_literal(
        "25",
        term.unsafe_named_node("http://www.w3.org/2001/XMLSchema#integer"),
      )),
    )

  // Use the quoted triple as an object
  let statement_about_statement =
    statement.Triple(
      term.SubjectNamed(term.unsafe_named_node("http://example.org/source1")),
      term.unsafe_named_node("http://example.org/states"),
      term.ObjectTriple(quoted_triple),
    )

  let graph_with_meta =
    graph.new()
    |> graph.add(statement_about_statement)

  let turtle_doc =
    turtle.TurtleDocument(
      base: None,
      prefixes: dict.new(),
      graph: graph_with_meta,
    )

  let result = turtle.serialize(turtle_doc)

  // Should contain the RDF-star syntax
  should.be_true(contains(result, "<<"))
  should.be_true(contains(result, ">>"))
  should.be_true(contains(result, "http://example.org/bob"))
  should.be_true(contains(result, "http://xmlns.com/foaf/0.1/age"))
  should.be_true(contains(result, "25"))
  should.be_true(contains(result, "http://example.org/source1"))
  should.be_true(contains(result, "http://example.org/states"))
}

// Nested Triple Terms

pub fn serialize_nested_triple_terms_test() {
  // Create a base quoted triple
  let base_triple =
    term.triple_term(
      term.SubjectNamed(term.unsafe_named_node("http://example.org/person1")),
      term.unsafe_named_node("http://xmlns.com/foaf/0.1/knows"),
      term.ObjectNamed(term.unsafe_named_node("http://example.org/person2")),
    )

  // Create a triple that has the first triple as its subject
  let meta_triple =
    term.triple_term(
      term.SubjectTriple(base_triple),
      term.unsafe_named_node("http://example.org/confidence"),
      term.ObjectLiteral(term.simple_literal("high")),
    )

  // Create a statement about the meta-triple
  let nested_statement =
    statement.Triple(
      term.SubjectNamed(term.unsafe_named_node("http://example.org/evaluator")),
      term.unsafe_named_node("http://example.org/evaluated"),
      term.ObjectTriple(meta_triple),
    )

  let graph_nested =
    graph.new()
    |> graph.add(nested_statement)

  let turtle_doc =
    turtle.TurtleDocument(base: None, prefixes: dict.new(), graph: graph_nested)

  let result = turtle.serialize(turtle_doc)

  // Should contain nested RDF-star syntax
  let double_angle_count =
    string.length(result) - string.length(string.replace(result, "<<", ""))
  should.be_true(double_angle_count >= 4)
  // At least two sets of << (4 chars removed)
  should.be_true(contains(result, "http://example.org/person1"))
  should.be_true(contains(result, "http://xmlns.com/foaf/0.1/knows"))
  should.be_true(contains(result, "http://example.org/person2"))
  should.be_true(contains(result, "\"high\""))
  should.be_true(contains(result, "http://example.org/evaluator"))
}

// TriG with RDF-star

pub fn serialize_triple_terms_in_named_graphs_test() {
  // Create quoted triple
  let quoted_triple =
    term.triple_term(
      term.SubjectNamed(term.unsafe_named_node("http://example.org/alice")),
      term.unsafe_named_node("http://xmlns.com/foaf/0.1/name"),
      term.ObjectLiteral(term.simple_literal("Alice")),
    )

  // Statement with quoted triple as subject
  let assertion_triple =
    statement.Triple(
      term.SubjectTriple(quoted_triple),
      term.unsafe_named_node("http://example.org/provenance"),
      term.ObjectNamed(term.unsafe_named_node("http://example.org/database1")),
    )

  let assertion_graph =
    graph.new()
    |> graph.add(assertion_triple)

  let graph_name =
    term.NamedGraph(term.unsafe_named_node("http://example.org/metadata"))
  let dataset_with_assertions =
    dataset.new()
    |> dataset.replace_graph(graph_name, assertion_graph)

  let trig_doc =
    trig.TrigDocument(
      base: None,
      prefixes: dict.new(),
      dataset: dataset_with_assertions,
    )

  let result = trig.serialize(trig_doc)

  // Should contain TriG named graph syntax with RDF-star
  should.be_true(contains(result, "<http://example.org/metadata>"))
  should.be_true(contains(result, "{"))
  should.be_true(contains(result, "}"))
  should.be_true(contains(result, "<<"))
  should.be_true(contains(result, ">>"))
  should.be_true(contains(result, "http://example.org/alice"))
  should.be_true(contains(result, "\"Alice\""))
  should.be_true(contains(result, "http://example.org/provenance"))
}

// Complex RDF 1.2 Scenarios

pub fn serialize_provenance_tracking_test() {
  let prefixes =
    dict.new()
    |> dict.insert("ex", "http://example.org/")
    |> dict.insert("foaf", "http://xmlns.com/foaf/0.1/")
    |> dict.insert("prov", "http://www.w3.org/ns/prov#")

  // Original fact
  let fact =
    term.triple_term(
      term.SubjectNamed(term.unsafe_named_node("http://example.org/alice")),
      term.unsafe_named_node("http://xmlns.com/foaf/0.1/age"),
      term.ObjectLiteral(term.typed_literal(
        "30",
        term.unsafe_named_node("http://www.w3.org/2001/XMLSchema#integer"),
      )),
    )

  // Provenance information
  let source_triple =
    statement.Triple(
      term.SubjectTriple(fact),
      term.unsafe_named_node("http://www.w3.org/ns/prov#wasAttributedTo"),
      term.ObjectNamed(term.unsafe_named_node("http://example.org/census2023")),
    )

  let confidence_triple =
    statement.Triple(
      term.SubjectTriple(fact),
      term.unsafe_named_node("http://example.org/confidence"),
      term.ObjectLiteral(term.typed_literal(
        "0.98",
        term.unsafe_named_node("http://www.w3.org/2001/XMLSchema#decimal"),
      )),
    )

  let time_triple =
    statement.Triple(
      term.SubjectTriple(fact),
      term.unsafe_named_node("http://www.w3.org/ns/prov#generatedAtTime"),
      term.ObjectLiteral(term.typed_literal(
        "2023-10-15T14:30:00Z",
        term.unsafe_named_node("http://www.w3.org/2001/XMLSchema#dateTime"),
      )),
    )

  let provenance_graph =
    graph.new()
    |> graph.add(source_triple)
    |> graph.add(confidence_triple)
    |> graph.add(time_triple)

  let turtle_doc =
    turtle.TurtleDocument(
      base: Some("http://example.org/"),
      prefixes: prefixes,
      graph: provenance_graph,
    )

  let result = turtle.serialize(turtle_doc)

  // Should use prefixes and contain all provenance data
  should.be_true(contains(result, "@base"))
  should.be_true(contains(result, "@prefix ex:"))
  should.be_true(contains(result, "@prefix prov:"))
  should.be_true(contains(result, "<<"))
  should.be_true(contains(result, ">>"))
  should.be_true(contains(result, "ex:alice"))
  should.be_true(contains(result, "foaf:age"))
  should.be_true(contains(result, "30"))
  should.be_true(contains(result, "prov:wasAttributedTo"))
  should.be_true(contains(result, "prov:generatedAtTime"))
  should.be_true(contains(result, "0.98"))
}

pub fn serialize_annotation_chains_test() {
  // Base statement
  let base_statement =
    term.triple_term(
      term.SubjectNamed(term.unsafe_named_node("http://example.org/document1")),
      term.unsafe_named_node("http://purl.org/dc/terms/creator"),
      term.ObjectNamed(term.unsafe_named_node("http://example.org/author1")),
    )

  // First level annotation
  let annotation1 =
    term.triple_term(
      term.SubjectTriple(base_statement),
      term.unsafe_named_node("http://example.org/certainty"),
      term.ObjectLiteral(term.simple_literal("confirmed")),
    )

  // Second level annotation (annotation of an annotation)
  let annotation2 =
    statement.Triple(
      term.SubjectTriple(annotation1),
      term.unsafe_named_node("http://example.org/reviewedBy"),
      term.ObjectNamed(term.unsafe_named_node("http://example.org/reviewer1")),
    )

  let chain_graph =
    graph.new()
    |> graph.add(annotation2)

  let turtle_doc =
    turtle.TurtleDocument(base: None, prefixes: dict.new(), graph: chain_graph)

  let result = turtle.serialize(turtle_doc)

  // Should handle deeply nested annotations
  let angle_bracket_count =
    string.length(result) - string.length(string.replace(result, "<<", ""))
  should.be_true(angle_bracket_count >= 4)
  // Two levels of nesting (4 chars removed for 2 << occurrences)
  should.be_true(contains(result, "http://example.org/document1"))
  should.be_true(contains(result, "http://purl.org/dc/terms/creator"))
  should.be_true(contains(result, "http://example.org/author1"))
  should.be_true(contains(result, "\"confirmed\""))
  should.be_true(contains(result, "http://example.org/reviewer1"))
}

// Mixed Triple Terms and Regular Triples

pub fn serialize_mixed_statements_test() {
  // Regular triple
  let regular_triple =
    statement.Triple(
      term.SubjectNamed(term.unsafe_named_node("http://example.org/alice")),
      term.unsafe_named_node("http://xmlns.com/foaf/0.1/name"),
      term.ObjectLiteral(term.simple_literal("Alice")),
    )

  // Triple with quoted triple as object
  let quoted_triple =
    term.triple_term(
      term.SubjectNamed(term.unsafe_named_node("http://example.org/bob")),
      term.unsafe_named_node("http://xmlns.com/foaf/0.1/name"),
      term.ObjectLiteral(term.simple_literal("Bob")),
    )

  let meta_triple =
    statement.Triple(
      term.SubjectNamed(term.unsafe_named_node("http://example.org/database")),
      term.unsafe_named_node("http://example.org/contains"),
      term.ObjectTriple(quoted_triple),
    )

  let mixed_graph =
    graph.new()
    |> graph.add(regular_triple)
    |> graph.add(meta_triple)

  let turtle_doc =
    turtle.TurtleDocument(base: None, prefixes: dict.new(), graph: mixed_graph)

  let result = turtle.serialize(turtle_doc)

  // Should handle both regular and quoted triples
  should.be_true(contains(result, "\"Alice\""))
  // Regular triple
  should.be_true(contains(result, "<<"))
  // Quoted triple syntax
  should.be_true(contains(result, "\"Bob\""))
  // Inside quoted triple
  should.be_true(contains(result, "http://example.org/database"))
  should.be_true(contains(result, "http://example.org/contains"))
}

// Term Conversion Tests

pub fn term_conversion_with_triple_terms_test() {
  let triple_term =
    term.triple_term(
      term.SubjectNamed(term.unsafe_named_node("http://example.org/s")),
      term.unsafe_named_node("http://example.org/p"),
      term.ObjectNamed(term.unsafe_named_node("http://example.org/o")),
    )

  // Test converting to and from Term
  let quoted_term = term.QuotedTripleTerm(triple_term)

  // Convert to subject
  case term.subject_from_term(quoted_term) {
    Ok(term.SubjectTriple(recovered_triple)) -> {
      should.equal(recovered_triple, triple_term)
    }
    _ -> should.fail()
  }

  // Convert to object
  let object = term.object_from_term(quoted_term)
  case object {
    term.ObjectTriple(recovered_triple) -> {
      should.equal(recovered_triple, triple_term)
    }
    _ -> should.fail()
  }

  // Test round-trip
  let subject = term.SubjectTriple(triple_term)
  let recovered_term = term.term_from_subject(subject)
  should.equal(recovered_term, quoted_term)
}

// Error Cases

pub fn triple_term_cannot_be_graph_name_test() {
  let triple_term =
    term.triple_term(
      term.SubjectNamed(term.unsafe_named_node("http://example.org/s")),
      term.unsafe_named_node("http://example.org/p"),
      term.ObjectNamed(term.unsafe_named_node("http://example.org/o")),
    )

  let quoted_term = term.QuotedTripleTerm(triple_term)

  // Should not be able to use as graph name
  case term.graph_name_from_term(quoted_term) {
    Error(term.InvalidGraphNameTerm) -> Nil
    // Expected
    _ -> should.fail()
  }
}

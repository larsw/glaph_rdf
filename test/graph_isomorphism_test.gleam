import glaph_rdf/graph
import glaph_rdf/statement
import glaph_rdf/term
import gleam/list
import gleam/order
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

// Helper functions for creating test data

fn alice_iri() -> term.NamedNode {
  case term.named_node("http://example.org/alice") {
    Ok(node) -> node
    Error(_) -> panic as "Failed to create alice IRI"
  }
}

fn bob_iri() -> term.NamedNode {
  case term.named_node("http://example.org/bob") {
    Ok(node) -> node
    Error(_) -> panic as "Failed to create bob IRI"
  }
}

fn knows_predicate() -> term.NamedNode {
  case term.named_node("http://xmlns.com/foaf/0.1/knows") {
    Ok(node) -> node
    Error(_) -> panic as "Failed to create knows predicate"
  }
}

fn name_predicate() -> term.NamedNode {
  case term.named_node("http://xmlns.com/foaf/0.1/name") {
    Ok(node) -> node
    Error(_) -> panic as "Failed to create name predicate"
  }
}

fn blank_a() -> term.BlankNode {
  case term.blank_node("a") {
    Ok(node) -> node
    Error(_) -> panic as "Failed to create blank node a"
  }
}

fn blank_b() -> term.BlankNode {
  case term.blank_node("b") {
    Ok(node) -> node
    Error(_) -> panic as "Failed to create blank node b"
  }
}

fn blank_x() -> term.BlankNode {
  case term.blank_node("x") {
    Ok(node) -> node
    Error(_) -> panic as "Failed to create blank node x"
  }
}

fn blank_y() -> term.BlankNode {
  case term.blank_node("y") {
    Ok(node) -> node
    Error(_) -> panic as "Failed to create blank node y"
  }
}

// Basic Isomorphism Tests

pub fn identical_graphs_are_isomorphic_test() {
  let triple =
    statement.Triple(
      subject: term.SubjectNamed(alice_iri()),
      predicate: knows_predicate(),
      object: term.ObjectNamed(bob_iri()),
    )

  let graph1 = graph.from_list([triple])
  let graph2 = graph.from_list([triple])

  graph.isomorphic(graph1, graph2) |> should.be_true()
}

pub fn empty_graphs_are_isomorphic_test() {
  let graph1 = graph.new()
  let graph2 = graph.new()

  graph.isomorphic(graph1, graph2) |> should.be_true()
}

pub fn different_size_graphs_not_isomorphic_test() {
  let triple =
    statement.Triple(
      subject: term.SubjectNamed(alice_iri()),
      predicate: knows_predicate(),
      object: term.ObjectNamed(bob_iri()),
    )

  let graph1 = graph.from_list([triple])
  let graph2 = graph.new()

  graph.isomorphic(graph1, graph2) |> should.be_false()
}

pub fn completely_different_graphs_not_isomorphic_test() {
  let triple1 =
    statement.Triple(
      subject: term.SubjectNamed(alice_iri()),
      predicate: knows_predicate(),
      object: term.ObjectNamed(bob_iri()),
    )

  let triple2 =
    statement.Triple(
      subject: term.SubjectNamed(bob_iri()),
      predicate: name_predicate(),
      object: term.ObjectLiteral(term.simple_literal("Bob")),
    )

  let graph1 = graph.from_list([triple1])
  let graph2 = graph.from_list([triple2])

  graph.isomorphic(graph1, graph2) |> should.be_false()
}

// Blank Node Isomorphism Tests

pub fn same_blank_node_structure_isomorphic_test() {
  let triple1 =
    statement.Triple(
      subject: term.SubjectBlank(blank_a()),
      predicate: knows_predicate(),
      object: term.ObjectNamed(alice_iri()),
    )

  let triple2 =
    statement.Triple(
      subject: term.SubjectBlank(blank_x()),
      predicate: knows_predicate(),
      object: term.ObjectNamed(alice_iri()),
    )

  let graph1 = graph.from_list([triple1])
  let graph2 = graph.from_list([triple2])

  graph.isomorphic(graph1, graph2) |> should.be_true()
}

pub fn complex_blank_node_mapping_test() {
  // Graph 1: _:a knows _:b, _:b knows alice
  let triple1_1 =
    statement.Triple(
      subject: term.SubjectBlank(blank_a()),
      predicate: knows_predicate(),
      object: term.ObjectBlank(blank_b()),
    )
  let triple1_2 =
    statement.Triple(
      subject: term.SubjectBlank(blank_b()),
      predicate: knows_predicate(),
      object: term.ObjectNamed(alice_iri()),
    )

  // Graph 2: _:x knows _:y, _:y knows alice (same structure, different labels)
  let triple2_1 =
    statement.Triple(
      subject: term.SubjectBlank(blank_x()),
      predicate: knows_predicate(),
      object: term.ObjectBlank(blank_y()),
    )
  let triple2_2 =
    statement.Triple(
      subject: term.SubjectBlank(blank_y()),
      predicate: knows_predicate(),
      object: term.ObjectNamed(alice_iri()),
    )

  let graph1 = graph.from_list([triple1_1, triple1_2])
  let graph2 = graph.from_list([triple2_1, triple2_2])

  graph.isomorphic(graph1, graph2) |> should.be_true()
}

pub fn different_blank_node_structures_not_isomorphic_test() {
  // Graph 1: _:a knows alice
  let triple1 =
    statement.Triple(
      subject: term.SubjectBlank(blank_a()),
      predicate: knows_predicate(),
      object: term.ObjectNamed(alice_iri()),
    )

  // Graph 2: alice knows _:x (different structure)
  let triple2 =
    statement.Triple(
      subject: term.SubjectNamed(alice_iri()),
      predicate: knows_predicate(),
      object: term.ObjectBlank(blank_x()),
    )

  let graph1 = graph.from_list([triple1])
  let graph2 = graph.from_list([triple2])

  graph.isomorphic(graph1, graph2) |> should.be_false()
}

pub fn cyclic_blank_node_structures_test() {
  // Graph 1: _:a knows _:b, _:b knows _:a (cycle)
  let triple1_1 =
    statement.Triple(
      subject: term.SubjectBlank(blank_a()),
      predicate: knows_predicate(),
      object: term.ObjectBlank(blank_b()),
    )
  let triple1_2 =
    statement.Triple(
      subject: term.SubjectBlank(blank_b()),
      predicate: knows_predicate(),
      object: term.ObjectBlank(blank_a()),
    )

  // Graph 2: _:x knows _:y, _:y knows _:x (same cycle, different labels)
  let triple2_1 =
    statement.Triple(
      subject: term.SubjectBlank(blank_x()),
      predicate: knows_predicate(),
      object: term.ObjectBlank(blank_y()),
    )
  let triple2_2 =
    statement.Triple(
      subject: term.SubjectBlank(blank_y()),
      predicate: knows_predicate(),
      object: term.ObjectBlank(blank_x()),
    )

  let graph1 = graph.from_list([triple1_1, triple1_2])
  let graph2 = graph.from_list([triple2_1, triple2_2])

  graph.isomorphic(graph1, graph2) |> should.be_true()
}

// Literal Isomorphism Tests

pub fn graphs_with_different_literals_not_isomorphic_test() {
  let triple1 =
    statement.Triple(
      subject: term.SubjectNamed(alice_iri()),
      predicate: name_predicate(),
      object: term.ObjectLiteral(term.simple_literal("Alice")),
    )

  let triple2 =
    statement.Triple(
      subject: term.SubjectNamed(alice_iri()),
      predicate: name_predicate(),
      object: term.ObjectLiteral(term.simple_literal("Bob")),
    )

  let graph1 = graph.from_list([triple1])
  let graph2 = graph.from_list([triple2])

  graph.isomorphic(graph1, graph2) |> should.be_false()
}

pub fn graphs_with_same_literals_are_isomorphic_test() {
  let literal = term.simple_literal("Alice")

  let triple1 =
    statement.Triple(
      subject: term.SubjectBlank(blank_a()),
      predicate: name_predicate(),
      object: term.ObjectLiteral(literal),
    )

  let triple2 =
    statement.Triple(
      subject: term.SubjectBlank(blank_x()),
      predicate: name_predicate(),
      object: term.ObjectLiteral(literal),
    )

  let graph1 = graph.from_list([triple1])
  let graph2 = graph.from_list([triple2])

  graph.isomorphic(graph1, graph2) |> should.be_true()
}

// Canonicalization Tests

pub fn canonicalize_empty_graph_test() {
  let empty_graph = graph.new()
  let canonical = graph.canonicalize(empty_graph)

  graph.size(canonical) |> should.equal(0)
}

pub fn canonicalize_graph_without_blanks_unchanged_test() {
  let triple =
    statement.Triple(
      subject: term.SubjectNamed(alice_iri()),
      predicate: knows_predicate(),
      object: term.ObjectNamed(bob_iri()),
    )

  let original = graph.from_list([triple])
  let canonical = graph.canonicalize(original)

  graph.triples(canonical) |> should.equal([triple])
}

pub fn canonicalize_assigns_deterministic_blank_labels_test() {
  let triple1 =
    statement.Triple(
      subject: term.SubjectBlank(blank_a()),
      predicate: knows_predicate(),
      object: term.ObjectNamed(alice_iri()),
    )

  let triple2 =
    statement.Triple(
      subject: term.SubjectBlank(blank_b()),
      predicate: knows_predicate(),
      object: term.ObjectNamed(bob_iri()),
    )

  let graph1 = graph.from_list([triple1, triple2])
  let canonical1 = graph.canonicalize(graph1)

  // Create the same graph with different blank node labels
  let triple3 =
    statement.Triple(
      subject: term.SubjectBlank(blank_x()),
      predicate: knows_predicate(),
      object: term.ObjectNamed(alice_iri()),
    )

  let triple4 =
    statement.Triple(
      subject: term.SubjectBlank(blank_y()),
      predicate: knows_predicate(),
      object: term.ObjectNamed(bob_iri()),
    )

  let graph2 = graph.from_list([triple3, triple4])
  let canonical2 = graph.canonicalize(graph2)

  // Canonical forms should be identical
  let triples1 = graph.triples(canonical1) |> list.sort(compare_triples)
  let triples2 = graph.triples(canonical2) |> list.sort(compare_triples)

  should.equal(triples1, triples2)
}

// Multiple graph same structure different order test
pub fn isomorphism_order_independent_test() {
  let triple1 =
    statement.Triple(
      subject: term.SubjectNamed(alice_iri()),
      predicate: knows_predicate(),
      object: term.ObjectNamed(bob_iri()),
    )
  let triple2 =
    statement.Triple(
      subject: term.SubjectNamed(bob_iri()),
      predicate: name_predicate(),
      object: term.ObjectLiteral(term.simple_literal("Bob")),
    )

  // Same triples, different order
  let graph1 = graph.from_list([triple1, triple2])
  let graph2 = graph.from_list([triple2, triple1])

  // They should be isomorphic
  graph.isomorphic(graph1, graph2) |> should.be_true()
}

// Edge cases
pub fn single_blank_node_self_reference_test() {
  let triple1 =
    statement.Triple(
      subject: term.SubjectBlank(blank_a()),
      predicate: knows_predicate(),
      object: term.ObjectBlank(blank_a()),
    )

  let triple2 =
    statement.Triple(
      subject: term.SubjectBlank(blank_x()),
      predicate: knows_predicate(),
      object: term.ObjectBlank(blank_x()),
    )

  let graph1 = graph.from_list([triple1])
  let graph2 = graph.from_list([triple2])

  graph.isomorphic(graph1, graph2) |> should.be_true()
}

// Helper function for sorting triples (needed for deterministic comparison)
fn compare_triples(
  triple1: statement.Triple,
  triple2: statement.Triple,
) -> order.Order {
  // This is a simplified comparison - in practice you might need more sophisticated ordering
  let statement.Triple(s1, p1, o1) = triple1
  let statement.Triple(s2, p2, o2) = triple2

  case serialize_subject(s1) |> string.compare(serialize_subject(s2)) {
    order.Eq ->
      case serialize_predicate(p1) |> string.compare(serialize_predicate(p2)) {
        order.Eq -> serialize_object(o1) |> string.compare(serialize_object(o2))
        other -> other
      }
    other -> other
  }
}

fn serialize_subject(subject: term.Subject) -> String {
  case subject {
    term.SubjectNamed(term.NamedNode(iri)) -> "N:" <> iri
    term.SubjectBlank(term.BlankNode(id)) -> "B:" <> id
    term.SubjectTriple(_) -> "T:QUOTED"
  }
}

fn serialize_predicate(predicate: term.Predicate) -> String {
  let term.NamedNode(iri) = predicate
  "P:" <> iri
}

fn serialize_object(object: term.Object) -> String {
  case object {
    term.ObjectNamed(term.NamedNode(iri)) -> "N:" <> iri
    term.ObjectBlank(term.BlankNode(id)) -> "B:" <> id
    term.ObjectLiteral(term.SimpleLiteral(value)) -> "L:" <> value
    term.ObjectLiteral(term.LanguageTaggedLiteral(value, term.LanguageTag(lang))) ->
      "L:" <> value <> "@" <> lang
    term.ObjectLiteral(term.TypedLiteral(value, term.NamedNode(datatype))) ->
      "L:" <> value <> "^^" <> datatype
    term.ObjectTriple(_) -> "T:QUOTED"
  }
}

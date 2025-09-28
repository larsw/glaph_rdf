import glaph_rdf/dataset
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

fn graph1_iri() -> term.NamedNode {
  case term.named_node("http://example.org/graph1") {
    Ok(node) -> node
    Error(_) -> panic as "Failed to create graph1 IRI"
  }
}

fn graph2_iri() -> term.NamedNode {
  case term.named_node("http://example.org/graph2") {
    Ok(node) -> node
    Error(_) -> panic as "Failed to create graph2 IRI"
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

fn blank_g1() -> term.BlankNode {
  case term.blank_node("g1") {
    Ok(node) -> node
    Error(_) -> panic as "Failed to create blank node g1"
  }
}

fn blank_g2() -> term.BlankNode {
  case term.blank_node("g2") {
    Ok(node) -> node
    Error(_) -> panic as "Failed to create blank node g2"
  }
}

// Basic Dataset Isomorphism Tests

pub fn identical_datasets_are_isomorphic_test() {
  let triple =
    statement.Triple(
      subject: term.SubjectNamed(alice_iri()),
      predicate: knows_predicate(),
      object: term.ObjectNamed(bob_iri()),
    )
  let quad =
    statement.Quad(
      subject: triple.subject,
      predicate: triple.predicate,
      object: triple.object,
      graph: term.DefaultGraph,
    )

  let dataset1 = dataset.from_list([quad])
  let dataset2 = dataset.from_list([quad])

  dataset.isomorphic(dataset1, dataset2) |> should.be_true()
}

pub fn empty_datasets_are_isomorphic_test() {
  let dataset1 = dataset.new()
  let dataset2 = dataset.new()

  dataset.isomorphic(dataset1, dataset2) |> should.be_true()
}

pub fn different_size_datasets_not_isomorphic_test() {
  let triple =
    statement.Triple(
      subject: term.SubjectNamed(alice_iri()),
      predicate: knows_predicate(),
      object: term.ObjectNamed(bob_iri()),
    )
  let quad =
    statement.Quad(
      subject: triple.subject,
      predicate: triple.predicate,
      object: triple.object,
      graph: term.DefaultGraph,
    )

  let dataset1 = dataset.from_list([quad])
  let dataset2 = dataset.new()

  dataset.isomorphic(dataset1, dataset2) |> should.be_false()
}

// Default Graph Isomorphism Tests

pub fn default_graph_with_blank_nodes_isomorphic_test() {
  let triple1 =
    statement.Triple(
      subject: term.SubjectBlank(blank_a()),
      predicate: knows_predicate(),
      object: term.ObjectNamed(alice_iri()),
    )
  let quad1 =
    statement.Quad(
      subject: triple1.subject,
      predicate: triple1.predicate,
      object: triple1.object,
      graph: term.DefaultGraph,
    )

  let triple2 =
    statement.Triple(
      subject: term.SubjectBlank(blank_x()),
      predicate: knows_predicate(),
      object: term.ObjectNamed(alice_iri()),
    )
  let quad2 =
    statement.Quad(
      subject: triple2.subject,
      predicate: triple2.predicate,
      object: triple2.object,
      graph: term.DefaultGraph,
    )

  let dataset1 = dataset.from_list([quad1])
  let dataset2 = dataset.from_list([quad2])

  dataset.isomorphic(dataset1, dataset2) |> should.be_true()
}

pub fn default_graph_different_structure_not_isomorphic_test() {
  let triple1 =
    statement.Triple(
      subject: term.SubjectBlank(blank_a()),
      predicate: knows_predicate(),
      object: term.ObjectNamed(alice_iri()),
    )
  let quad1 =
    statement.Quad(
      subject: triple1.subject,
      predicate: triple1.predicate,
      object: triple1.object,
      graph: term.DefaultGraph,
    )

  let triple2 =
    statement.Triple(
      subject: term.SubjectNamed(alice_iri()),
      predicate: knows_predicate(),
      object: term.ObjectBlank(blank_x()),
    )
  let quad2 =
    statement.Quad(
      subject: triple2.subject,
      predicate: triple2.predicate,
      object: triple2.object,
      graph: term.DefaultGraph,
    )

  let dataset1 = dataset.from_list([quad1])
  let dataset2 = dataset.from_list([quad2])

  dataset.isomorphic(dataset1, dataset2) |> should.be_false()
}

// Named Graph Isomorphism Tests

pub fn named_graphs_with_same_structure_isomorphic_test() {
  let triple1 =
    statement.Triple(
      subject: term.SubjectBlank(blank_a()),
      predicate: knows_predicate(),
      object: term.ObjectNamed(alice_iri()),
    )
  let quad1 =
    statement.Quad(
      subject: triple1.subject,
      predicate: triple1.predicate,
      object: triple1.object,
      graph: term.NamedGraph(graph1_iri()),
    )

  let triple2 =
    statement.Triple(
      subject: term.SubjectBlank(blank_x()),
      predicate: knows_predicate(),
      object: term.ObjectNamed(alice_iri()),
    )
  let quad2 =
    statement.Quad(
      subject: triple2.subject,
      predicate: triple2.predicate,
      object: triple2.object,
      graph: term.NamedGraph(graph1_iri()),
    )

  let dataset1 = dataset.from_list([quad1])
  let dataset2 = dataset.from_list([quad2])

  dataset.isomorphic(dataset1, dataset2) |> should.be_true()
}

pub fn different_named_graphs_not_isomorphic_test() {
  let triple =
    statement.Triple(
      subject: term.SubjectNamed(alice_iri()),
      predicate: knows_predicate(),
      object: term.ObjectNamed(bob_iri()),
    )

  let quad1 =
    statement.Quad(
      subject: triple.subject,
      predicate: triple.predicate,
      object: triple.object,
      graph: term.NamedGraph(graph1_iri()),
    )

  let quad2 =
    statement.Quad(
      subject: triple.subject,
      predicate: triple.predicate,
      object: triple.object,
      graph: term.NamedGraph(graph2_iri()),
    )

  let dataset1 = dataset.from_list([quad1])
  let dataset2 = dataset.from_list([quad2])

  dataset.isomorphic(dataset1, dataset2) |> should.be_false()
}

// Multiple Graph Isomorphism Tests

pub fn multiple_graphs_with_blank_nodes_isomorphic_test() {
  // Dataset 1: Default graph with _:a knows alice, Named graph with _:b knows bob
  let default_triple1 =
    statement.Triple(
      subject: term.SubjectBlank(blank_a()),
      predicate: knows_predicate(),
      object: term.ObjectNamed(alice_iri()),
    )
  let default_quad1 =
    statement.Quad(
      subject: default_triple1.subject,
      predicate: default_triple1.predicate,
      object: default_triple1.object,
      graph: term.DefaultGraph,
    )

  let named_triple1 =
    statement.Triple(
      subject: term.SubjectBlank(blank_b()),
      predicate: knows_predicate(),
      object: term.ObjectNamed(bob_iri()),
    )
  let named_quad1 =
    statement.Quad(
      subject: named_triple1.subject,
      predicate: named_triple1.predicate,
      object: named_triple1.object,
      graph: term.NamedGraph(graph1_iri()),
    )

  // Dataset 2: Same structure with different blank node labels
  let default_triple2 =
    statement.Triple(
      subject: term.SubjectBlank(blank_x()),
      predicate: knows_predicate(),
      object: term.ObjectNamed(alice_iri()),
    )
  let default_quad2 =
    statement.Quad(
      subject: default_triple2.subject,
      predicate: default_triple2.predicate,
      object: default_triple2.object,
      graph: term.DefaultGraph,
    )

  let named_triple2 =
    statement.Triple(
      subject: term.SubjectBlank(blank_y()),
      predicate: knows_predicate(),
      object: term.ObjectNamed(bob_iri()),
    )
  let named_quad2 =
    statement.Quad(
      subject: named_triple2.subject,
      predicate: named_triple2.predicate,
      object: named_triple2.object,
      graph: term.NamedGraph(graph1_iri()),
    )

  let dataset1 = dataset.from_list([default_quad1, named_quad1])
  let dataset2 = dataset.from_list([default_quad2, named_quad2])

  dataset.isomorphic(dataset1, dataset2) |> should.be_true()
}

pub fn multiple_graphs_different_content_not_isomorphic_test() {
  // Dataset 1: alice in default, bob in named graph
  let default_triple1 =
    statement.Triple(
      subject: term.SubjectNamed(alice_iri()),
      predicate: name_predicate(),
      object: term.ObjectLiteral(term.simple_literal("Alice")),
    )
  let default_quad1 =
    statement.Quad(
      subject: default_triple1.subject,
      predicate: default_triple1.predicate,
      object: default_triple1.object,
      graph: term.DefaultGraph,
    )

  let named_triple1 =
    statement.Triple(
      subject: term.SubjectNamed(bob_iri()),
      predicate: name_predicate(),
      object: term.ObjectLiteral(term.simple_literal("Bob")),
    )
  let named_quad1 =
    statement.Quad(
      subject: named_triple1.subject,
      predicate: named_triple1.predicate,
      object: named_triple1.object,
      graph: term.NamedGraph(graph1_iri()),
    )

  // Dataset 2: bob in default, alice in named graph (swapped)
  let default_triple2 =
    statement.Triple(
      subject: term.SubjectNamed(bob_iri()),
      predicate: name_predicate(),
      object: term.ObjectLiteral(term.simple_literal("Bob")),
    )
  let default_quad2 =
    statement.Quad(
      subject: default_triple2.subject,
      predicate: default_triple2.predicate,
      object: default_triple2.object,
      graph: term.DefaultGraph,
    )

  let named_triple2 =
    statement.Triple(
      subject: term.SubjectNamed(alice_iri()),
      predicate: name_predicate(),
      object: term.ObjectLiteral(term.simple_literal("Alice")),
    )
  let named_quad2 =
    statement.Quad(
      subject: named_triple2.subject,
      predicate: named_triple2.predicate,
      object: named_triple2.object,
      graph: term.NamedGraph(graph1_iri()),
    )

  let dataset1 = dataset.from_list([default_quad1, named_quad1])
  let dataset2 = dataset.from_list([default_quad2, named_quad2])

  dataset.isomorphic(dataset1, dataset2) |> should.be_false()
}

// Blank Graph Name Tests

pub fn blank_graph_names_isomorphic_test() {
  let triple =
    statement.Triple(
      subject: term.SubjectNamed(alice_iri()),
      predicate: knows_predicate(),
      object: term.ObjectNamed(bob_iri()),
    )

  let quad1 =
    statement.Quad(
      subject: triple.subject,
      predicate: triple.predicate,
      object: triple.object,
      graph: term.BlankGraph(blank_g1()),
    )

  let quad2 =
    statement.Quad(
      subject: triple.subject,
      predicate: triple.predicate,
      object: triple.object,
      graph: term.BlankGraph(blank_g2()),
    )

  let dataset1 = dataset.from_list([quad1])
  let dataset2 = dataset.from_list([quad2])

  dataset.isomorphic(dataset1, dataset2) |> should.be_true()
}

pub fn mixed_blank_and_named_graphs_test() {
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

  // Dataset 1: triple1 in blank graph, triple2 in named graph
  let quad1_1 =
    statement.Quad(
      subject: triple1.subject,
      predicate: triple1.predicate,
      object: triple1.object,
      graph: term.BlankGraph(blank_g1()),
    )

  let quad1_2 =
    statement.Quad(
      subject: triple2.subject,
      predicate: triple2.predicate,
      object: triple2.object,
      graph: term.NamedGraph(graph1_iri()),
    )

  // Dataset 2: triple1 in named graph, triple2 in blank graph (different structure)
  let quad2_1 =
    statement.Quad(
      subject: triple1.subject,
      predicate: triple1.predicate,
      object: triple1.object,
      graph: term.NamedGraph(graph1_iri()),
    )

  let quad2_2 =
    statement.Quad(
      subject: triple2.subject,
      predicate: triple2.predicate,
      object: triple2.object,
      graph: term.BlankGraph(blank_g2()),
    )

  let dataset1 = dataset.from_list([quad1_1, quad1_2])
  let dataset2 = dataset.from_list([quad2_1, quad2_2])

  dataset.isomorphic(dataset1, dataset2) |> should.be_false()
}

// Canonicalization Tests

pub fn dataset_canonicalize_empty_test() {
  let empty_dataset = dataset.new()
  let canonical = dataset.canonicalize(empty_dataset)

  dataset.quad_count(canonical) |> should.equal(0)
}

pub fn dataset_canonicalize_no_blanks_unchanged_test() {
  let triple =
    statement.Triple(
      subject: term.SubjectNamed(alice_iri()),
      predicate: knows_predicate(),
      object: term.ObjectNamed(bob_iri()),
    )
  let quad =
    statement.Quad(
      subject: triple.subject,
      predicate: triple.predicate,
      object: triple.object,
      graph: term.DefaultGraph,
    )

  let original = dataset.from_list([quad])
  let canonical = dataset.canonicalize(original)

  dataset.quads(canonical) |> should.equal([quad])
}

pub fn dataset_canonicalize_deterministic_test() {
  // Create dataset with blank nodes
  let triple1 =
    statement.Triple(
      subject: term.SubjectBlank(blank_a()),
      predicate: knows_predicate(),
      object: term.ObjectNamed(alice_iri()),
    )
  let quad1 =
    statement.Quad(
      subject: triple1.subject,
      predicate: triple1.predicate,
      object: triple1.object,
      graph: term.DefaultGraph,
    )

  let dataset1 = dataset.from_list([quad1])
  let canonical1 = dataset.canonicalize(dataset1)

  // Create equivalent dataset with different blank node labels
  let triple2 =
    statement.Triple(
      subject: term.SubjectBlank(blank_x()),
      predicate: knows_predicate(),
      object: term.ObjectNamed(alice_iri()),
    )
  let quad2 =
    statement.Quad(
      subject: triple2.subject,
      predicate: triple2.predicate,
      object: triple2.object,
      graph: term.DefaultGraph,
    )

  let dataset2 = dataset.from_list([quad2])
  let canonical2 = dataset.canonicalize(dataset2)

  // Canonical forms should be identical
  let quads1 = dataset.quads(canonical1) |> list.sort(compare_quads)
  let quads2 = dataset.quads(canonical2) |> list.sort(compare_quads)

  should.equal(quads1, quads2)
}

// Edge Cases

pub fn dataset_isomorphism_order_independent_test() {
  let triple1 =
    statement.Triple(
      subject: term.SubjectBlank(blank_a()),
      predicate: knows_predicate(),
      object: term.ObjectNamed(alice_iri()),
    )
  let quad1 =
    statement.Quad(
      subject: triple1.subject,
      predicate: triple1.predicate,
      object: triple1.object,
      graph: term.DefaultGraph,
    )

  let triple2 =
    statement.Triple(
      subject: term.SubjectNamed(bob_iri()),
      predicate: name_predicate(),
      object: term.ObjectLiteral(term.simple_literal("Bob")),
    )
  let quad2 =
    statement.Quad(
      subject: triple2.subject,
      predicate: triple2.predicate,
      object: triple2.object,
      graph: term.NamedGraph(graph1_iri()),
    )

  // Same quads, different order
  let dataset1 = dataset.from_list([quad1, quad2])
  let dataset2 = dataset.from_list([quad2, quad1])

  dataset.isomorphic(dataset1, dataset2) |> should.be_true()
}

// Helper function for sorting quads (needed for deterministic comparison)
fn compare_quads(quad1: statement.Quad, quad2: statement.Quad) -> order.Order {
  let statement.Quad(s1, p1, o1, g1) = quad1
  let statement.Quad(s2, p2, o2, g2) = quad2

  case serialize_subject(s1) |> string.compare(serialize_subject(s2)) {
    order.Eq ->
      case serialize_predicate(p1) |> string.compare(serialize_predicate(p2)) {
        order.Eq ->
          case serialize_object(o1) |> string.compare(serialize_object(o2)) {
            order.Eq ->
              serialize_graph_name(g1)
              |> string.compare(serialize_graph_name(g2))
            other -> other
          }
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

fn serialize_graph_name(graph_name: term.GraphName) -> String {
  case graph_name {
    term.DefaultGraph -> "G:DEFAULT"
    term.NamedGraph(term.NamedNode(iri)) -> "G:N:" <> iri
    term.BlankGraph(term.BlankNode(id)) -> "G:B:" <> id
  }
}

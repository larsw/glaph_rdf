import glaph_rdf/graph
import glaph_rdf/serializers/ntriples
import glaph_rdf/statement
import glaph_rdf/term
import gleam/list
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

// Basic N-Triples Serialization Tests

pub fn serialize_simple_triple_test() {
  let alice_node = case term.named_node("http://example.org/alice") {
    Ok(node) -> node
    Error(_) -> panic as "Failed to create named node"
  }
  let name_predicate = case term.named_node("http://xmlns.com/foaf/0.1/name") {
    Ok(node) -> node
    Error(_) -> panic as "Failed to create named node"
  }

  let triple =
    statement.Triple(
      subject: term.SubjectNamed(alice_node),
      predicate: name_predicate,
      object: term.ObjectLiteral(term.simple_literal("Alice")),
    )

  let graph_with_triple = graph.new() |> graph.add(triple)
  let nt_text = ntriples.serialize_graph(graph_with_triple)

  should.equal(
    nt_text,
    "<http://example.org/alice> <http://xmlns.com/foaf/0.1/name> \"Alice\" .\n",
  )
}

pub fn serialize_typed_literal_test() {
  let alice_node = case term.named_node("http://example.org/alice") {
    Ok(node) -> node
    Error(_) -> panic as "Failed to create named node"
  }
  let age_predicate = case term.named_node("http://xmlns.com/foaf/0.1/age") {
    Ok(node) -> node
    Error(_) -> panic as "Failed to create named node"
  }
  let int_datatype = case
    term.named_node("http://www.w3.org/2001/XMLSchema#integer")
  {
    Ok(node) -> node
    Error(_) -> panic as "Failed to create named node"
  }

  let triple =
    statement.Triple(
      subject: term.SubjectNamed(alice_node),
      predicate: age_predicate,
      object: term.ObjectLiteral(term.typed_literal("30", int_datatype)),
    )

  let nt_text = ntriples.serialize_graph(graph.new() |> graph.add(triple))

  should.be_true(contains(
    nt_text,
    "\"30\"^^<http://www.w3.org/2001/XMLSchema#integer>",
  ))
}

pub fn serialize_language_literal_test() {
  let alice_node = case term.named_node("http://example.org/alice") {
    Ok(node) -> node
    Error(_) -> panic as "Failed to create named node"
  }
  let name_predicate = case term.named_node("http://xmlns.com/foaf/0.1/name") {
    Ok(node) -> node
    Error(_) -> panic as "Failed to create named node"
  }
  let lang_tag = case term.language_tag("en") {
    Ok(tag) -> tag
    Error(_) -> panic as "Failed to create language tag"
  }

  let triple =
    statement.Triple(
      subject: term.SubjectNamed(alice_node),
      predicate: name_predicate,
      object: term.ObjectLiteral(term.language_literal("Alice", lang_tag)),
    )

  let nt_text = ntriples.serialize_graph(graph.new() |> graph.add(triple))

  should.be_true(contains(nt_text, "\"Alice\"@en"))
}

pub fn serialize_blank_node_test() {
  let blank_node = case term.blank_node("n1") {
    Ok(node) -> node
    Error(_) -> panic as "Failed to create blank node"
  }
  let name_predicate = case term.named_node("http://xmlns.com/foaf/0.1/name") {
    Ok(node) -> node
    Error(_) -> panic as "Failed to create named node"
  }

  let triple =
    statement.Triple(
      subject: term.SubjectBlank(blank_node),
      predicate: name_predicate,
      object: term.ObjectLiteral(term.simple_literal("Anonymous")),
    )

  let nt_text = ntriples.serialize_graph(graph.new() |> graph.add(triple))

  should.be_true(contains(nt_text, "_:n1"))
  should.be_true(contains(nt_text, "\"Anonymous\""))
}

// Basic N-Triples Parsing Tests

pub fn parse_simple_triple_test() {
  let nt_text =
    "<http://example.org/alice> <http://xmlns.com/foaf/0.1/name> \"Alice\" ."

  case ntriples.parse(nt_text) {
    Ok(document) -> {
      let triples = graph.triples(document.graph)
      should.equal(list.length(triples), 1)

      case triples {
        [triple] -> {
          let statement.Triple(
            subject: subject,
            predicate: predicate,
            object: object,
          ) = triple

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
        _ -> should.fail()
      }
    }
    Error(ntriples.NTriplesError(_, _)) -> {
      should.fail()
    }
  }
}

pub fn parse_typed_literal_test() {
  let nt_text =
    "<http://example.org/alice> <http://xmlns.com/foaf/0.1/age> \"30\"^^<http://www.w3.org/2001/XMLSchema#integer> ."

  case ntriples.parse(nt_text) {
    Ok(document) -> {
      let triples = graph.triples(document.graph)
      should.equal(list.length(triples), 1)

      case triples {
        [triple] -> {
          let statement.Triple(object: object, ..) = triple
          case object {
            term.ObjectLiteral(term.TypedLiteral(value, datatype)) -> {
              should.equal(value, "30")
              let term.NamedNode(dt_iri) = datatype
              should.equal(dt_iri, "http://www.w3.org/2001/XMLSchema#integer")
            }
            _ -> should.fail()
          }
        }
        _ -> should.fail()
      }
    }
    Error(_) -> should.fail()
  }
}

pub fn parse_language_literal_test() {
  let nt_text =
    "<http://example.org/alice> <http://xmlns.com/foaf/0.1/name> \"Alice\"@en ."

  case ntriples.parse(nt_text) {
    Ok(document) -> {
      let triples = graph.triples(document.graph)
      case triples {
        [triple] -> {
          let statement.Triple(object: object, ..) = triple
          case object {
            term.ObjectLiteral(term.LanguageTaggedLiteral(value, lang_tag)) -> {
              should.equal(value, "Alice")
              let term.LanguageTag(lang) = lang_tag
              should.equal(lang, "en")
            }
            _ -> should.fail()
          }
        }
        _ -> should.fail()
      }
    }
    Error(_) -> should.fail()
  }
}

pub fn parse_blank_node_test() {
  let nt_text = "_:alice <http://xmlns.com/foaf/0.1/name> \"Alice\" ."

  case ntriples.parse(nt_text) {
    Ok(document) -> {
      let triples = graph.triples(document.graph)
      case triples {
        [triple] -> {
          let statement.Triple(subject: subject, ..) = triple
          case subject {
            term.SubjectBlank(term.BlankNode(id)) -> should.equal(id, "alice")
            _ -> should.fail()
          }
        }
        _ -> should.fail()
      }
    }
    Error(_) -> should.fail()
  }
}

pub fn parse_multiple_triples_test() {
  let nt_text =
    "<http://example.org/alice> <http://xmlns.com/foaf/0.1/name> \"Alice\" .
<http://example.org/alice> <http://xmlns.com/foaf/0.1/age> \"30\"^^<http://www.w3.org/2001/XMLSchema#integer> ."

  case ntriples.parse(nt_text) {
    Ok(document) -> {
      let triples = graph.triples(document.graph)
      should.equal(list.length(triples), 2)
    }
    Error(_) -> should.fail()
  }
}

pub fn parse_empty_lines_test() {
  let nt_text =
    "<http://example.org/alice> <http://xmlns.com/foaf/0.1/name> \"Alice\" .

<http://example.org/bob> <http://xmlns.com/foaf/0.1/name> \"Bob\" .
"

  case ntriples.parse(nt_text) {
    Ok(document) -> {
      let triples = graph.triples(document.graph)
      should.equal(list.length(triples), 2)
    }
    Error(_) -> should.fail()
  }
}

// String Escaping Parse Tests

pub fn parse_escaped_string_test() {
  let nt_text =
    "<http://example.org/test> <http://example.org/value> \"Line 1\\nLine 2\\tTabbed\\\"Quoted\\\"\" ."

  case ntriples.parse(nt_text) {
    Ok(document) -> {
      let triples = graph.triples(document.graph)
      case triples {
        [triple] -> {
          let statement.Triple(object: object, ..) = triple
          case object {
            term.ObjectLiteral(term.SimpleLiteral(value)) ->
              should.equal(value, "Line 1\nLine 2\tTabbed\"Quoted\"")
            _ -> should.fail()
          }
        }
        _ -> should.fail()
      }
    }
    Error(_) -> should.fail()
  }
}

// Round-trip Tests

pub fn round_trip_simple_triple_test() {
  let alice_node = case term.named_node("http://example.org/alice") {
    Ok(node) -> node
    Error(_) -> panic as "Failed to create named node"
  }
  let name_predicate = case term.named_node("http://xmlns.com/foaf/0.1/name") {
    Ok(node) -> node
    Error(_) -> panic as "Failed to create named node"
  }

  let original_triple =
    statement.Triple(
      subject: term.SubjectNamed(alice_node),
      predicate: name_predicate,
      object: term.ObjectLiteral(term.simple_literal("Alice")),
    )

  let original_graph = graph.new() |> graph.add(original_triple)
  let serialized = ntriples.serialize_graph(original_graph)

  case ntriples.parse(serialized) {
    Ok(parsed_doc) -> {
      let parsed_triples = graph.triples(parsed_doc.graph)
      should.equal(list.length(parsed_triples), 1)
      should.equal(parsed_triples, [original_triple])
    }
    Error(_) -> should.fail()
  }
}

// Error Cases

pub fn parse_missing_dot_test() {
  let nt_text =
    "<http://example.org/alice> <http://xmlns.com/foaf/0.1/name> \"Alice\""

  case ntriples.parse(nt_text) {
    Ok(_) -> should.fail()
    Error(ntriples.NTriplesError(_message, line)) -> {
      should.equal(line, 1)
    }
  }
}

pub fn parse_unterminated_string_test() {
  let nt_text =
    "<http://example.org/alice> <http://xmlns.com/foaf/0.1/name> \"Alice ."

  case ntriples.parse(nt_text) {
    Ok(_) -> should.fail()
    Error(ntriples.NTriplesError(_message, line)) -> {
      should.equal(line, 1)
    }
  }
}

pub fn parse_incomplete_triple_test() {
  let nt_text = "<http://example.org/alice> <http://xmlns.com/foaf/0.1/name> ."

  case ntriples.parse(nt_text) {
    Ok(_) -> should.fail()
    Error(ntriples.NTriplesError(_message, line)) -> {
      should.equal(line, 1)
    }
  }
}

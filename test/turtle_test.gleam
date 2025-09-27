//// Tests for the Turtle RDF serializer
//// 
//// This module provides comprehensive tests for parsing and serializing
//// RDF documents in Turtle format, covering:
//// 
//// - Basic triple parsing and serialization
//// - Prefix and base URI handling
//// - All literal types (strings, numbers, booleans, language-tagged, typed)
//// - Blank nodes and named nodes
//// - RDF type shorthand ('a')
//// - Multiple triples with semicolon and comma separators
//// - Comments and whitespace handling
//// - Escape sequences and Unicode
//// - Error handling for malformed input
//// - Round-trip parsing/serialization consistency

import glaph_rdf/graph
import glaph_rdf/serializers/turtle
import glaph_rdf/statement
import glaph_rdf/term
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

// Test basic parsing of simple triples
pub fn parse_simple_triple_test() {
  let turtle_text =
    "<http://example.org/subject> <http://example.org/predicate> <http://example.org/object> ."

  let assert Ok(document) = turtle.parse(turtle_text)
  let triples = graph.triples(document.graph)

  should.equal(1, graph.size(document.graph))

  let assert [triple] = triples
  let assert term.SubjectNamed(term.NamedNode(subject_iri)) = triple.subject
  should.equal("http://example.org/subject", subject_iri)

  let term.NamedNode(predicate_iri) = triple.predicate
  should.equal("http://example.org/predicate", predicate_iri)

  let assert term.ObjectNamed(term.NamedNode(object_iri)) = triple.object
  should.equal("http://example.org/object", object_iri)
}

// Test parsing with prefixes
pub fn parse_with_prefixes_test() {
  let turtle_text =
    "@prefix ex: <http://example.org/> .
ex:subject ex:predicate ex:object ."

  let assert Ok(document) = turtle.parse(turtle_text)
  should.equal(1, graph.size(document.graph))

  let triples = graph.triples(document.graph)
  let assert [triple] = triples

  let assert term.SubjectNamed(term.NamedNode(subject_iri)) = triple.subject
  should.equal("http://example.org/subject", subject_iri)

  let term.NamedNode(predicate_iri) = triple.predicate
  should.equal("http://example.org/predicate", predicate_iri)

  let assert term.ObjectNamed(term.NamedNode(object_iri)) = triple.object
  should.equal("http://example.org/object", object_iri)
}

// Test parsing with base URI
pub fn parse_with_base_test() {
  let turtle_text =
    "@base <http://example.org/> .
<subject> <predicate> <object> ."

  let assert Ok(document) = turtle.parse(turtle_text)
  should.equal(1, graph.size(document.graph))
  should.equal(Some("http://example.org/"), document.base)

  let triples = graph.triples(document.graph)
  let assert [triple] = triples

  let assert term.SubjectNamed(term.NamedNode(subject_iri)) = triple.subject
  should.equal("http://example.org/subject", subject_iri)
}

// Test parsing string literals
pub fn parse_string_literal_test() {
  let turtle_text =
    "<http://example.org/subject> <http://example.org/name> \"John Doe\" ."

  let assert Ok(document) = turtle.parse(turtle_text)
  let triples = graph.triples(document.graph)
  let assert [triple] = triples

  let assert term.ObjectLiteral(literal) = triple.object
  let assert term.SimpleLiteral(value) = literal
  should.equal("John Doe", value)
}

// Test parsing language-tagged literals
pub fn parse_language_tagged_literal_test() {
  let turtle_text =
    "<http://example.org/subject> <http://example.org/name> \"Hello\"@en ."

  let assert Ok(document) = turtle.parse(turtle_text)
  let triples = graph.triples(document.graph)
  let assert [triple] = triples

  let assert term.ObjectLiteral(term.LanguageTaggedLiteral(
    value,
    term.LanguageTag(lang),
  )) = triple.object
  should.equal("Hello", value)
  should.equal("en", lang)
}

// Test parsing typed literals
pub fn parse_typed_literal_test() {
  let turtle_text =
    "<http://example.org/subject> <http://example.org/age> \"25\"^^<http://www.w3.org/2001/XMLSchema#integer> ."

  let assert Ok(document) = turtle.parse(turtle_text)
  let triples = graph.triples(document.graph)
  let assert [triple] = triples

  let assert term.ObjectLiteral(term.TypedLiteral(
    value,
    term.NamedNode(datatype_iri),
  )) = triple.object
  should.equal("25", value)
  should.equal("http://www.w3.org/2001/XMLSchema#integer", datatype_iri)
}

// Test parsing numeric literals
pub fn parse_numeric_literals_test() {
  let turtle_text =
    "<http://example.org/s> <http://example.org/int> 42 .
<http://example.org/s> <http://example.org/decimal> 3.14 .
<http://example.org/s> <http://example.org/double> 1.23e4 ."

  let assert Ok(document) = turtle.parse(turtle_text)
  should.equal(3, graph.size(document.graph))
}

// Test parsing boolean literals
pub fn parse_boolean_literals_test() {
  let turtle_text =
    "<http://example.org/s> <http://example.org/true> true .
<http://example.org/s> <http://example.org/false> false ."

  let assert Ok(document) = turtle.parse(turtle_text)
  should.equal(2, graph.size(document.graph))
}

// Test parsing blank nodes
pub fn parse_blank_node_test() {
  let turtle_text =
    "_:blank1 <http://example.org/predicate> <http://example.org/object> ."

  let assert Ok(document) = turtle.parse(turtle_text)
  let triples = graph.triples(document.graph)
  let assert [triple] = triples

  let assert term.SubjectBlank(term.BlankNode(identifier)) = triple.subject
  should.equal("blank1", identifier)
}

// Test parsing with 'a' shorthand for rdf:type
pub fn parse_rdf_type_shorthand_test() {
  let turtle_text =
    "<http://example.org/subject> a <http://example.org/Person> ."

  let assert Ok(document) = turtle.parse(turtle_text)
  let triples = graph.triples(document.graph)
  let assert [triple] = triples

  let term.NamedNode(predicate_iri) = triple.predicate
  should.equal("http://www.w3.org/1999/02/22-rdf-syntax-ns#type", predicate_iri)
}

// Test parsing multiple triples with semicolon
pub fn parse_semicolon_separator_test() {
  let turtle_text =
    "<http://example.org/subject> <http://example.org/name> \"John\" ; 
                                                      <http://example.org/age> 30 ."

  let assert Ok(document) = turtle.parse(turtle_text)
  should.equal(2, graph.size(document.graph))
}

// Test parsing multiple objects with comma
pub fn parse_comma_separator_test() {
  let turtle_text =
    "<http://example.org/subject> <http://example.org/knows> <http://example.org/alice>, <http://example.org/bob> ."

  let assert Ok(document) = turtle.parse(turtle_text)
  should.equal(2, graph.size(document.graph))
}

// Test parsing with comments
pub fn parse_with_comments_test() {
  let turtle_text =
    "# This is a comment
<http://example.org/subject> <http://example.org/predicate> <http://example.org/object> . # End comment"

  let assert Ok(document) = turtle.parse(turtle_text)
  should.equal(1, graph.size(document.graph))
}

// Test parsing with escaped strings
pub fn parse_escaped_strings_test() {
  let turtle_text =
    "<http://example.org/subject> <http://example.org/quote> \"He said \\\"Hello\\\"\" ."

  let assert Ok(document) = turtle.parse(turtle_text)
  let triples = graph.triples(document.graph)
  let assert [triple] = triples

  let assert term.ObjectLiteral(literal) = triple.object
  let assert term.SimpleLiteral(value) = literal
  should.equal("He said \"Hello\"", value)
}

// Test parsing Unicode escapes
pub fn parse_unicode_escapes_test() {
  let turtle_text =
    "<http://example.org/subject> <http://example.org/text> \"Hello \\u0041\" ."

  let assert Ok(document) = turtle.parse(turtle_text)
  let triples = graph.triples(document.graph)
  let assert [triple] = triples

  let assert term.ObjectLiteral(literal) = triple.object
  let assert term.SimpleLiteral(value) = literal
  should.equal("Hello A", value)
}

// Test error handling - unterminated string
pub fn parse_error_unterminated_string_test() {
  let turtle_text =
    "<http://example.org/subject> <http://example.org/predicate> \"unterminated ."

  let assert Error(turtle.TurtleError(message, _)) = turtle.parse(turtle_text)
  should.be_true(string.contains(message, "Unterminated string"))
}

// Test error handling - invalid IRI
pub fn parse_error_invalid_character_test() {
  let turtle_text = "@ invalid"

  let assert Error(turtle.TurtleError(message, _)) = turtle.parse(turtle_text)
  should.be_true(string.contains(message, "Expected language tag"))
}

// Test serialization of simple document
pub fn serialize_simple_document_test() {
  let assert Ok(subject) = term.named_node("http://example.org/subject")
  let assert Ok(predicate) = term.named_node("http://example.org/predicate")
  let assert Ok(object) = term.named_node("http://example.org/object")

  let triple =
    statement.triple(
      term.SubjectNamed(subject),
      predicate,
      term.ObjectNamed(object),
    )

  let graph_val = graph.from_list([triple])
  let document =
    turtle.TurtleDocument(base: None, prefixes: dict.new(), graph: graph_val)

  let serialized = turtle.serialize(document)
  should.be_true(string.contains(serialized, "<http://example.org/subject>"))
  should.be_true(string.contains(serialized, "<http://example.org/predicate>"))
  should.be_true(string.contains(serialized, "<http://example.org/object>"))
}

// Test serialization with prefixes
pub fn serialize_with_prefixes_test() {
  let assert Ok(subject) = term.named_node("http://example.org/subject")
  let assert Ok(predicate) = term.named_node("http://example.org/predicate")
  let assert Ok(object) = term.named_node("http://example.org/object")

  let triple =
    statement.triple(
      term.SubjectNamed(subject),
      predicate,
      term.ObjectNamed(object),
    )

  let prefixes = dict.from_list([#("ex", "http://example.org/")])
  let graph_val = graph.from_list([triple])
  let document =
    turtle.TurtleDocument(base: None, prefixes: prefixes, graph: graph_val)

  let serialized = turtle.serialize(document)
  should.be_true(string.contains(serialized, "@prefix ex:"))
  should.be_true(string.contains(serialized, "ex:subject"))
  should.be_true(string.contains(serialized, "ex:predicate"))
  should.be_true(string.contains(serialized, "ex:object"))
}

// Test serialization with base URI
pub fn serialize_with_base_test() {
  let assert Ok(subject) = term.named_node("http://example.org/subject")
  let assert Ok(predicate) = term.named_node("http://example.org/predicate")
  let assert Ok(object) = term.named_node("http://example.org/object")

  let triple =
    statement.triple(
      term.SubjectNamed(subject),
      predicate,
      term.ObjectNamed(object),
    )

  let graph_val = graph.from_list([triple])
  let document =
    turtle.TurtleDocument(
      base: Some("http://example.org/"),
      prefixes: dict.new(),
      graph: graph_val,
    )

  let serialized = turtle.serialize(document)
  should.be_true(string.contains(serialized, "@base <http://example.org/>"))
}

// Test serialization of literals
pub fn serialize_literals_test() {
  let assert Ok(subject) = term.named_node("http://example.org/subject")
  let assert Ok(name_pred) = term.named_node("http://example.org/name")
  let assert Ok(age_pred) = term.named_node("http://example.org/age")
  let assert Ok(active_pred) = term.named_node("http://example.org/active")

  let name_literal = term.SimpleLiteral("John Doe")
  let assert Ok(age_datatype) =
    term.named_node("http://www.w3.org/2001/XMLSchema#integer")
  let age_literal = term.TypedLiteral("30", age_datatype)
  let assert Ok(lang_tag) = term.language_tag("en")
  let lang_literal = term.LanguageTaggedLiteral("Hello", lang_tag)

  let triples = [
    statement.triple(
      term.SubjectNamed(subject),
      name_pred,
      term.ObjectLiteral(name_literal),
    ),
    statement.triple(
      term.SubjectNamed(subject),
      age_pred,
      term.ObjectLiteral(age_literal),
    ),
    statement.triple(
      term.SubjectNamed(subject),
      active_pred,
      term.ObjectLiteral(lang_literal),
    ),
  ]

  let graph_val = graph.from_list(triples)
  let document =
    turtle.TurtleDocument(base: None, prefixes: dict.new(), graph: graph_val)

  let serialized = turtle.serialize(document)
  should.be_true(string.contains(serialized, "\"John Doe\""))
  // Note: numeric literals might be serialized without quotes for built-in types
  should.be_true(
    string.contains(serialized, "30") || string.contains(serialized, "\"30\""),
  )
  should.be_true(string.contains(serialized, "\"Hello\"@en"))
}

// Test serialization of blank nodes
pub fn serialize_blank_nodes_test() {
  let assert Ok(blank) = term.blank_node("node1")
  let assert Ok(predicate) = term.named_node("http://example.org/predicate")
  let assert Ok(object) = term.named_node("http://example.org/object")

  let triple =
    statement.triple(
      term.SubjectBlank(blank),
      predicate,
      term.ObjectNamed(object),
    )

  let graph_val = graph.from_list([triple])
  let document =
    turtle.TurtleDocument(base: None, prefixes: dict.new(), graph: graph_val)

  let serialized = turtle.serialize(document)
  should.be_true(string.contains(serialized, "_:node1"))
}

// Test serialization of rdf:type as 'a'
pub fn serialize_rdf_type_shorthand_test() {
  let assert Ok(subject) = term.named_node("http://example.org/subject")
  let assert Ok(rdf_type) =
    term.named_node("http://www.w3.org/1999/02/22-rdf-syntax-ns#type")
  let assert Ok(person_class) = term.named_node("http://example.org/Person")

  let triple =
    statement.triple(
      term.SubjectNamed(subject),
      rdf_type,
      term.ObjectNamed(person_class),
    )

  let graph_val = graph.from_list([triple])
  let document =
    turtle.TurtleDocument(base: None, prefixes: dict.new(), graph: graph_val)

  let serialized = turtle.serialize(document)
  should.be_true(string.contains(serialized, " a "))
}

// Test round-trip: parse then serialize
pub fn roundtrip_test() {
  let original_turtle =
    "@prefix ex: <http://example.org/> .
@base <http://example.org/> .

ex:subject ex:predicate \"literal value\" ;
           ex:other \"typed literal\"^^<http://www.w3.org/2001/XMLSchema#string> ;
           ex:lang \"language tagged\"@en .

_:blank ex:predicate ex:object ."

  let assert Ok(parsed) = turtle.parse(original_turtle)
  let serialized = turtle.serialize(parsed)
  let assert Ok(reparsed) = turtle.parse(serialized)

  // Compare graph sizes - they should be the same
  should.equal(graph.size(parsed.graph), graph.size(reparsed.graph))
}

// Test serialization with special characters that need escaping
pub fn serialize_escaped_strings_test() {
  let assert Ok(subject) = term.named_node("http://example.org/subject")
  let assert Ok(predicate) = term.named_node("http://example.org/quote")

  let quote_literal = term.SimpleLiteral("He said \"Hello\"")
  let newline_literal = term.SimpleLiteral("Line 1\nLine 2")
  let tab_literal = term.SimpleLiteral("Column1\tColumn2")

  let triples = [
    statement.triple(
      term.SubjectNamed(subject),
      predicate,
      term.ObjectLiteral(quote_literal),
    ),
    statement.triple(
      term.SubjectNamed(subject),
      predicate,
      term.ObjectLiteral(newline_literal),
    ),
    statement.triple(
      term.SubjectNamed(subject),
      predicate,
      term.ObjectLiteral(tab_literal),
    ),
  ]

  let graph_val = graph.from_list(triples)
  let document =
    turtle.TurtleDocument(base: None, prefixes: dict.new(), graph: graph_val)

  let serialized = turtle.serialize(document)
  should.be_true(string.contains(serialized, "\\\""))
  should.be_true(string.contains(serialized, "\\n"))
  should.be_true(string.contains(serialized, "\\t"))
}

// Test parsing graph only (utility function)
pub fn parse_graph_only_test() {
  let turtle_text =
    "<http://example.org/s> <http://example.org/p> <http://example.org/o> ."

  let assert Ok(graph_result) = turtle.parse_graph(turtle_text)
  should.equal(1, graph.size(graph_result))
}

// Test serialize_graph utility function
pub fn serialize_graph_only_test() {
  let assert Ok(subject) = term.named_node("http://example.org/subject")
  let assert Ok(predicate) = term.named_node("http://example.org/predicate")
  let assert Ok(object) = term.named_node("http://example.org/object")

  let triple =
    statement.triple(
      term.SubjectNamed(subject),
      predicate,
      term.ObjectNamed(object),
    )

  let graph_val = graph.from_list([triple])
  let prefixes = dict.from_list([#("ex", "http://example.org/")])

  let serialized =
    turtle.serialize_graph(graph_val, Some("http://example.org/"), prefixes)
  should.be_true(string.contains(serialized, "@base"))
  should.be_true(string.contains(serialized, "@prefix ex:"))
}

// Test empty document
pub fn parse_empty_document_test() {
  let turtle_text = ""

  let assert Ok(document) = turtle.parse(turtle_text)
  should.equal(0, graph.size(document.graph))
  should.equal(None, document.base)
  should.equal(dict.new(), document.prefixes)
}

// Test document with only prefixes and base
pub fn parse_prefixes_only_test() {
  let turtle_text =
    "@prefix ex: <http://example.org/> .
@base <http://example.org/base/> ."

  let assert Ok(document) = turtle.parse(turtle_text)
  should.equal(0, graph.size(document.graph))
  should.equal(Some("http://example.org/base/"), document.base)

  let assert Ok(prefix_iri) = dict.get(document.prefixes, "ex")
  should.equal("http://example.org/", prefix_iri)
}

// Test parsing multiple prefixes
pub fn parse_multiple_prefixes_test() {
  let turtle_text =
    "@prefix ex: <http://example.org/> .
@prefix foaf: <http://xmlns.com/foaf/0.1/> .
@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .

ex:john foaf:name \"John Doe\" ;
        rdf:type foaf:Person ."

  let assert Ok(document) = turtle.parse(turtle_text)
  should.equal(2, graph.size(document.graph))

  // Check all prefixes are parsed
  let assert Ok(ex_iri) = dict.get(document.prefixes, "ex")
  should.equal("http://example.org/", ex_iri)
  let assert Ok(foaf_iri) = dict.get(document.prefixes, "foaf")
  should.equal("http://xmlns.com/foaf/0.1/", foaf_iri)
  let assert Ok(rdf_iri) = dict.get(document.prefixes, "rdf")
  should.equal("http://www.w3.org/1999/02/22-rdf-syntax-ns#", rdf_iri)
}

// Test empty prefix (default namespace)
pub fn parse_empty_prefix_test() {
  let turtle_text =
    "@prefix : <http://example.org/> .
:subject :predicate :object ."

  let assert Ok(document) = turtle.parse(turtle_text)
  should.equal(1, graph.size(document.graph))

  let assert Ok(default_iri) = dict.get(document.prefixes, "")
  should.equal("http://example.org/", default_iri)

  let triples = graph.triples(document.graph)
  let assert [triple] = triples
  let assert term.SubjectNamed(term.NamedNode(subject_iri)) = triple.subject
  should.equal("http://example.org/subject", subject_iri)
}

// Test prefix with empty local name
pub fn parse_prefix_empty_local_test() {
  let turtle_text =
    "@prefix ex: <http://example.org/> .
ex: <http://example.org/predicate> \"empty local name\" ."

  let assert Ok(document) = turtle.parse(turtle_text)
  should.equal(1, graph.size(document.graph))

  let triples = graph.triples(document.graph)
  let assert [triple] = triples
  let assert term.SubjectNamed(term.NamedNode(subject_iri)) = triple.subject
  should.equal("http://example.org/", subject_iri)
}

// Test prefix redefinition (later definition should override)
pub fn parse_prefix_redefinition_test() {
  let turtle_text =
    "@prefix ex: <http://old.example.org/> .
@prefix ex: <http://new.example.org/> .
ex:subject ex:predicate ex:object ."

  let assert Ok(document) = turtle.parse(turtle_text)
  should.equal(1, graph.size(document.graph))

  // Should use the later definition
  let assert Ok(ex_iri) = dict.get(document.prefixes, "ex")
  should.equal("http://new.example.org/", ex_iri)

  let triples = graph.triples(document.graph)
  let assert [triple] = triples
  let assert term.SubjectNamed(term.NamedNode(subject_iri)) = triple.subject
  should.equal("http://new.example.org/subject", subject_iri)
}

// Test prefixed names in all triple positions
pub fn parse_prefixed_names_all_positions_test() {
  let turtle_text =
    "@prefix ex: <http://example.org/> .
@prefix foaf: <http://xmlns.com/foaf/0.1/> .

ex:person foaf:knows ex:friend ."

  let assert Ok(document) = turtle.parse(turtle_text)
  should.equal(1, graph.size(document.graph))

  let triples = graph.triples(document.graph)
  let assert [triple] = triples

  let assert term.SubjectNamed(term.NamedNode(subject_iri)) = triple.subject
  should.equal("http://example.org/person", subject_iri)

  let term.NamedNode(predicate_iri) = triple.predicate
  should.equal("http://xmlns.com/foaf/0.1/knows", predicate_iri)

  let assert term.ObjectNamed(term.NamedNode(object_iri)) = triple.object
  should.equal("http://example.org/friend", object_iri)
}

// Test prefixed names with complex local names
pub fn parse_complex_prefixed_names_test() {
  let turtle_text =
    "@prefix ex: <http://example.org/> .

ex:person123 ex:hasProperty ex:somevalue ;
             ex:hasDash ex:underScore ;
             ex:camelCase ex:PascalCase ."

  let assert Ok(document) = turtle.parse(turtle_text)
  should.equal(3, graph.size(document.graph))

  // Verify that complex local names are properly parsed
  let triples = graph.triples(document.graph)

  // All subjects should be the same
  let subjects =
    triples
    |> list.map(fn(triple) { triple.subject })
    |> list.unique

  should.equal(1, list.length(subjects))
  let assert [term.SubjectNamed(term.NamedNode(subject_iri))] = subjects
  should.equal("http://example.org/person123", subject_iri)
}

// Test prefixed datatypes
pub fn parse_prefixed_datatypes_test() {
  let turtle_text =
    "@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
@prefix ex: <http://example.org/> .

ex:person ex:age \"25\"^^xsd:integer ;
         ex:height \"5.9\"^^xsd:decimal ;
         ex:score \"1.23e4\"^^xsd:double ."

  let assert Ok(document) = turtle.parse(turtle_text)
  should.equal(3, graph.size(document.graph))

  // Just verify that prefixed datatypes are properly parsed and expanded
  let assert Ok(xsd_iri) = dict.get(document.prefixes, "xsd")
  should.equal("http://www.w3.org/2001/XMLSchema#", xsd_iri)
}

// Test serialization prefers prefixes over full IRIs
pub fn serialize_prefers_prefixes_test() {
  let assert Ok(subject) = term.named_node("http://example.org/person")
  let assert Ok(predicate) = term.named_node("http://xmlns.com/foaf/0.1/name")
  let assert Ok(object) = term.named_node("http://example.org/john")

  let triple =
    statement.triple(
      term.SubjectNamed(subject),
      predicate,
      term.ObjectNamed(object),
    )

  let prefixes =
    dict.from_list([
      #("ex", "http://example.org/"),
      #("foaf", "http://xmlns.com/foaf/0.1/"),
    ])
  let graph_val = graph.from_list([triple])
  let document =
    turtle.TurtleDocument(base: None, prefixes: prefixes, graph: graph_val)

  let serialized = turtle.serialize(document)

  // Should use prefixed forms, not full IRIs
  should.be_true(string.contains(serialized, "ex:person"))
  should.be_true(string.contains(serialized, "foaf:name"))
  should.be_true(string.contains(serialized, "ex:john"))

  // Should not contain full IRIs
  should.be_false(string.contains(serialized, "<http://example.org/person>"))
  should.be_false(string.contains(
    serialized,
    "<http://xmlns.com/foaf/0.1/name>",
  ))
}

// Test serialization chooses best prefix match
pub fn serialize_best_prefix_match_test() {
  let assert Ok(subject1) =
    term.named_node("http://example.org/path/deep/resource")
  let assert Ok(subject2) = term.named_node("http://example.org/path/resource")
  let assert Ok(predicate) = term.named_node("http://example.org/predicate")
  let assert Ok(object) = term.named_node("http://example.org/object")

  let triples = [
    statement.triple(
      term.SubjectNamed(subject1),
      predicate,
      term.ObjectNamed(object),
    ),
    statement.triple(
      term.SubjectNamed(subject2),
      predicate,
      term.ObjectNamed(object),
    ),
  ]

  // Define overlapping prefixes - the longer one should be preferred
  let prefixes =
    dict.from_list([
      #("ex", "http://example.org/"),
      #("deep", "http://example.org/path/deep/"),
    ])
  let graph_val = graph.from_list(triples)
  let document =
    turtle.TurtleDocument(base: None, prefixes: prefixes, graph: graph_val)

  let serialized = turtle.serialize(document)

  // Should use the more specific prefix for the deep resource
  should.be_true(string.contains(serialized, "deep:resource"))
  // Should use the general prefix for the shallow resource
  should.be_true(string.contains(serialized, "ex:path/resource"))
}

// Test serialization with empty prefix
pub fn serialize_empty_prefix_test() {
  let assert Ok(subject) = term.named_node("http://example.org/subject")
  let assert Ok(predicate) = term.named_node("http://example.org/predicate")
  let assert Ok(object) = term.named_node("http://example.org/object")

  let triple =
    statement.triple(
      term.SubjectNamed(subject),
      predicate,
      term.ObjectNamed(object),
    )

  let prefixes = dict.from_list([#("", "http://example.org/")])
  let graph_val = graph.from_list([triple])
  let document =
    turtle.TurtleDocument(base: None, prefixes: prefixes, graph: graph_val)

  let serialized = turtle.serialize(document)

  // Should use empty prefix notation
  should.be_true(string.contains(serialized, ":subject"))
  should.be_true(string.contains(serialized, ":predicate"))
  should.be_true(string.contains(serialized, ":object"))

  // Should declare empty prefix
  should.be_true(string.contains(serialized, "@prefix :"))
}

// Test error handling for undefined prefix
pub fn parse_undefined_prefix_error_test() {
  let turtle_text =
    "@prefix ex: <http://example.org/> .
undefined:subject ex:predicate ex:object ."

  let assert Error(turtle.TurtleError(message, _)) = turtle.parse(turtle_text)
  should.be_true(string.contains(message, "Unknown prefix"))
}

// Test prefix case sensitivity
pub fn parse_prefix_case_sensitivity_test() {
  let turtle_text =
    "@prefix Ex: <http://example.org/uppercase/> .
@prefix ex: <http://example.org/lowercase/> .

Ex:subject ex:predicate Ex:object ."

  let assert Ok(document) = turtle.parse(turtle_text)
  should.equal(1, graph.size(document.graph))

  // Both prefixes should exist
  let assert Ok(upper_iri) = dict.get(document.prefixes, "Ex")
  should.equal("http://example.org/uppercase/", upper_iri)
  let assert Ok(lower_iri) = dict.get(document.prefixes, "ex")
  should.equal("http://example.org/lowercase/", lower_iri)

  let triples = graph.triples(document.graph)
  let assert [triple] = triples

  // Subject should use uppercase prefix
  let assert term.SubjectNamed(term.NamedNode(subject_iri)) = triple.subject
  should.equal("http://example.org/uppercase/subject", subject_iri)

  // Predicate should use lowercase prefix
  let term.NamedNode(predicate_iri) = triple.predicate
  should.equal("http://example.org/lowercase/predicate", predicate_iri)

  // Object should use uppercase prefix
  let assert term.ObjectNamed(term.NamedNode(object_iri)) = triple.object
  should.equal("http://example.org/uppercase/object", object_iri)
}

// Test prefix with trailing fragment/query should work
pub fn parse_prefix_with_trailing_chars_test() {
  let turtle_text =
    "@prefix ex: <http://example.org/#> .
@prefix query: <http://example.org/?> .

ex:subject query:predicate \"value\" ."

  let assert Ok(document) = turtle.parse(turtle_text)
  should.equal(1, graph.size(document.graph))

  let triples = graph.triples(document.graph)
  let assert [triple] = triples

  let assert term.SubjectNamed(term.NamedNode(subject_iri)) = triple.subject
  should.equal("http://example.org/#subject", subject_iri)

  let term.NamedNode(predicate_iri) = triple.predicate
  should.equal("http://example.org/?predicate", predicate_iri)
}

import gleeunit
import gleeunit/should
import gleam/uri
import glaph_rdf
import glaph_rdf/dataset as dataset_mod
import glaph_rdf/graph as graph_mod
import glaph_rdf/statement as statement_mod
import glaph_rdf/term as term_mod

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn term_validation_test() {
  let assert Ok(term_mod.NamedNode(value: iri)) = glaph_rdf.named_node("https://example.org/id")
  should.equal("https://example.org/id", iri)

  let assert Error(term_mod.InvalidIri("example")) = glaph_rdf.named_node("example")
  let assert Ok(term_mod.NamedNode(value: unicode_iri)) =
    glaph_rdf.named_node("https://例え.テスト/パス?クエリ=値#フラグ")
  should.equal("https://例え.テスト/パス?クエリ=値#フラグ", unicode_iri)
  let assert Error(term_mod.InvalidIri("http://exa mple.org")) =
    glaph_rdf.named_node("http://exa mple.org")

  let assert Ok(term_mod.BlankNode(identifier: "_b1")) = glaph_rdf.blank_node("_b1")
  let assert Error(term_mod.InvalidBlankNodeIdentifier("bad id")) = glaph_rdf.blank_node("bad id")

  let assert Ok(term_mod.LanguageTag(value: "en-US")) = glaph_rdf.language_tag("en-US")
  let assert Error(term_mod.InvalidLanguageTag("invalid_tag")) = glaph_rdf.language_tag("invalid_tag")
  let assert Ok(term_mod.LanguageTag(value: "zh-Hant-TW")) =
    glaph_rdf.language_tag("zh-Hant-TW")
  let assert Ok(term_mod.LanguageTag(value: "en-gb-oed")) =
    glaph_rdf.language_tag("en-gb-oed")
  let assert Ok(term_mod.LanguageTag(value: "x-private")) =
    glaph_rdf.language_tag("x-private")
  let assert Ok(term_mod.LanguageTag(value: "i-klingon")) =
    glaph_rdf.language_tag("i-klingon")
  let assert Error(term_mod.InvalidLanguageTag("x")) = glaph_rdf.language_tag("x")
  let assert Error(term_mod.InvalidLanguageTag("en-")) = glaph_rdf.language_tag("en-")

  let literal_term = term_mod.LiteralTerm(glaph_rdf.simple_literal("value"))
  let assert Error(term_mod.InvalidSubjectTerm) = glaph_rdf.subject_from_term(literal_term)
}

pub fn triple_construction_test() {
  let assert Ok(ex) = glaph_rdf.named_node("http://example.com/subject")
  let assert Ok(pred) = glaph_rdf.named_node("http://example.com/predicate")
  let assert Ok(obj_node) = glaph_rdf.named_node("http://example.com/object")

  let subject = term_mod.SubjectNamed(ex)
  let object = term_mod.ObjectNamed(obj_node)
  let triple = glaph_rdf.triple(subject, pred, object)

  glaph_rdf.new_dataset()
  |> glaph_rdf.dataset_add_triple(triple)
  |> glaph_rdf.dataset_contains_triple(triple, term_mod.DefaultGraph)
  |> should.be_true
}

pub fn graph_operations_test() {
  let assert Ok(ex) = glaph_rdf.named_node("https://example.org/ex")
  let assert Ok(pred) = glaph_rdf.named_node("https://example.org/p")
  let assert Ok(obj) = glaph_rdf.named_node("https://example.org/o")

  let triple = statement_mod.triple(term_mod.SubjectNamed(ex), pred, term_mod.ObjectNamed(obj))

  let graph = graph_mod.new()
  let graph = graph_mod.add(graph, triple)
  graph_mod.contains(graph, triple) |> should.be_true
  should.equal(1, graph_mod.size(graph))

  let graph = graph_mod.add(graph, triple)
  should.equal(1, graph_mod.size(graph))

  let graph = graph_mod.remove(graph, triple)
  should.equal(0, graph_mod.size(graph))
}

pub fn dataset_operations_test() {
  let assert Ok(ex) = glaph_rdf.named_node("https://example.org/ex")
  let assert Ok(pred) = glaph_rdf.named_node("https://example.org/p")
  let assert Ok(obj) = glaph_rdf.named_node("https://example.org/o")
  let assert Ok(name) = glaph_rdf.named_node("https://example.org/graph")

  let triple = statement_mod.triple(term_mod.SubjectNamed(ex), pred, term_mod.ObjectNamed(obj))
  let default_dataset = dataset_mod.add_triple(dataset_mod.new(), triple)

  should.equal(1, dataset_mod.quad_count(default_dataset))
  dataset_mod.default_graph(default_dataset)
  |> graph_mod.contains(triple)
  |> should.be_true

  let quad = statement_mod.quad(triple, term_mod.NamedGraph(name))
  let dataset = dataset_mod.add_quad(default_dataset, quad)

  should.equal(2, dataset_mod.quad_count(dataset))
  dataset_mod.graph(dataset, term_mod.NamedGraph(name))
  |> graph_mod.contains(triple)
  |> should.be_true

  should.equal([term_mod.NamedGraph(name)], dataset_mod.graph_names(dataset))
}

pub fn dataset_mutation_test() {
  let assert Ok(subject_node) = glaph_rdf.named_node("https://example.org/subject")
  let assert Ok(predicate_node) = glaph_rdf.named_node("https://example.org/predicate")
  let assert Ok(object_node) = glaph_rdf.named_node("https://example.org/object")
  let assert Ok(graph_name) = glaph_rdf.named_node("https://example.org/graph")
  let assert Ok(other_object) = glaph_rdf.named_node("https://example.org/object-2")

  let triple = statement_mod.triple(
    term_mod.SubjectNamed(subject_node),
    predicate_node,
    term_mod.ObjectNamed(object_node),
  )
  let quad = statement_mod.quad(triple, term_mod.NamedGraph(graph_name))

  let dataset = dataset_mod.add_quad(dataset_mod.new(), quad)
  dataset_mod.contains_quad(dataset, quad) |> should.be_true

  let dataset = dataset_mod.remove_quad(dataset, quad)
  dataset_mod.contains_quad(dataset, quad) |> should.be_false

  let dataset = dataset_mod.add_quad(dataset_mod.new(), quad)
  let emptied = dataset_mod.remove_graph(dataset, term_mod.NamedGraph(graph_name))
  dataset_mod.contains_quad(emptied, quad) |> should.be_false

  let replacement_triple = statement_mod.triple(
    term_mod.SubjectNamed(subject_node),
    predicate_node,
    term_mod.ObjectNamed(other_object),
  )
  let replacement_graph = graph_mod.from_list([replacement_triple])
  let replaced = dataset_mod.replace_graph(dataset, term_mod.NamedGraph(graph_name), replacement_graph)

  dataset_mod.contains_triple(replaced, replacement_triple, term_mod.NamedGraph(graph_name))
  |> should.be_true
  dataset_mod.contains_triple(replaced, triple, term_mod.NamedGraph(graph_name))
  |> should.be_false
}

pub fn dataset_merge_test() {
  let assert Ok(subject_a) = glaph_rdf.named_node("https://example.org/a")
  let assert Ok(subject_b) = glaph_rdf.named_node("https://example.org/b")
  let assert Ok(predicate) = glaph_rdf.named_node("https://example.org/p")
  let assert Ok(obj) = glaph_rdf.named_node("https://example.org/o")

  let triple_a = statement_mod.triple(
    term_mod.SubjectNamed(subject_a),
    predicate,
    term_mod.ObjectNamed(obj),
  )

  let triple_b = statement_mod.triple(
    term_mod.SubjectNamed(subject_b),
    predicate,
    term_mod.ObjectNamed(obj),
  )

  let dataset_a = dataset_mod.add_triple(dataset_mod.new(), triple_a)
  let dataset_b = dataset_mod.add_triple(dataset_mod.new(), triple_b)

  let merged = dataset_mod.merge(dataset_a, dataset_b)
  should.equal(2, dataset_mod.quad_count(merged))
  dataset_mod.contains_triple(merged, triple_a, term_mod.DefaultGraph) |> should.be_true
  dataset_mod.contains_triple(merged, triple_b, term_mod.DefaultGraph) |> should.be_true
}

pub fn quad_from_terms_validation_test() {
  let assert Ok(subject) = glaph_rdf.named_node("https://example.org/s")
  let assert Ok(predicate) = glaph_rdf.named_node("https://example.org/p")
  let assert Ok(object_node) = glaph_rdf.named_node("https://example.org/o")
  let assert Ok(graph_name) = glaph_rdf.named_node("https://example.org/g")

  let subject_term = term_mod.NamedTerm(subject)
  let object_term = term_mod.NamedTerm(object_node)
  let graph_term = term_mod.NamedGraph(graph_name)

  let assert Ok(triple) = glaph_rdf.triple_from_terms(subject_term, predicate, object_term)
  let assert Ok(quad) = glaph_rdf.quad_from_terms(subject_term, predicate, object_term, graph_term)

  should.equal(triple, statement_mod.triple_from_quad(quad))

  let literal_term = term_mod.LiteralTerm(glaph_rdf.simple_literal("value"))
  let assert Error(term_mod.InvalidSubjectTerm) =
    glaph_rdf.triple_from_terms(literal_term, predicate, object_term)
}

pub fn iri_uri_roundtrip_test() {
  let iri = "https://例え.テスト/パス?クエリ=値#フラグ"
  let assert Ok(node) = glaph_rdf.named_node(iri)
  let assert Ok(uri_value) = glaph_rdf.named_node_to_uri(node)
  let assert Ok(roundtrip) = glaph_rdf.uri_to_iri(uri_value)
  should.equal(iri, roundtrip)

  let encoded_unicode = "https://example.org/%E3%81%82"
  let assert Ok(decoded_unicode) = glaph_rdf.decode_iri(encoded_unicode)
  should.equal("https://example.org/あ", decoded_unicode)

  let ascii_encoded = "https://example.org/%7Euser"
  let assert Ok(decoded_ascii) = glaph_rdf.decode_iri(ascii_encoded)
  should.equal(ascii_encoded, decoded_ascii)

  let uri_string = uri.to_string(uri_value)
  let assert Ok(parsed_uri) = uri.parse(uri_string)
  let assert Ok(node_from_uri) = glaph_rdf.named_node_from_uri(parsed_uri)
  should.equal(node, node_from_uri)
}

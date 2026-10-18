//// Regression tests for RDF 1.2 directional language-tagged strings
//// (`"value"@tag--ltr` / `--rtl`, datatype `rdf:dirLangString`) in the term
//// model, N-Triples, N-Quads and isomorphism. Every test runs on both Erlang
//// and JavaScript.

import glaph_rdf
import glaph_rdf/dataset
import glaph_rdf/graph
import glaph_rdf/serializers/nquads
import glaph_rdf/serializers/ntriples
import glaph_rdf/statement
import glaph_rdf/term
import gleam/int
import gleam/list
import gleam/string
import gleeunit/should
import simplifile

// Helpers ---------------------------------------------------------------------

fn iri(value: String) -> term.NamedNode {
  let assert Ok(node) = term.named_node(value)
  node
}

fn lang(value: String) -> term.LanguageTag {
  let assert Ok(tag) = term.language_tag(value)
  tag
}

fn s() -> term.Subject {
  term.SubjectNamed(iri("http://ex.org/s"))
}

fn p() -> term.Predicate {
  iri("http://ex.org/p")
}

fn g() -> term.GraphName {
  term.NamedGraph(iri("http://ex.org/g"))
}

fn dir_literal(
  value: String,
  tag: String,
  direction: term.BaseDirection,
) -> term.Literal {
  term.directional_language_literal(value, lang(tag), direction)
}

fn nt_object(text: String) -> term.Object {
  let assert Ok(doc) = ntriples.parse(text)
  let assert [triple] = graph.triples(doc.graph)
  triple.object
}

fn nq_single(text: String) -> statement.Quad {
  let assert Ok(doc) = nquads.parse(text)
  let assert [quad] = dataset.quads(doc.dataset)
  quad
}

fn nt_error(text: String) -> String {
  let assert Error(ntriples.NTriplesError(message, 1)) = ntriples.parse(text)
  message
}

fn nq_error(text: String) -> String {
  let assert Error(nquads.NQuadsError(message, 1)) = nquads.parse(text)
  message
}

/// Runs `work` on a fresh path under `build/` and deletes the file again.
fn with_path(name: String, work: fn(String) -> a) -> a {
  let path =
    "build/tmp_dirlang_"
    <> name
    <> "_"
    <> int.to_string(int.random(1_000_000_000))
  let result = work(path)
  let _ = simplifile.delete(path)
  result
}

// Term model --------------------------------------------------------------------

pub fn base_direction_parses_ltr_and_rtl_test() {
  term.base_direction("ltr") |> should.equal(Ok(term.LeftToRight))
  term.base_direction("rtl") |> should.equal(Ok(term.RightToLeft))
}

/// RDF 1.2 Concepts 3.4: the base direction MUST be the lowercase string
/// `ltr` or `rtl`. Uppercase or mixed case was accepted and lowercased.
pub fn base_direction_is_case_sensitive_test() {
  term.base_direction("LTR")
  |> should.equal(Error(term.InvalidBaseDirection("LTR")))
  term.base_direction("Rtl")
  |> should.equal(Error(term.InvalidBaseDirection("Rtl")))
  term.base_direction("rTL")
  |> should.equal(Error(term.InvalidBaseDirection("rTL")))
  glaph_rdf.base_direction("RTL")
  |> should.equal(Error(term.InvalidBaseDirection("RTL")))
}

pub fn base_direction_rejects_other_values_test() {
  term.base_direction("up")
  |> should.equal(Error(term.InvalidBaseDirection("up")))
  term.base_direction("") |> should.equal(Error(term.InvalidBaseDirection("")))
  term.base_direction("ltr ")
  |> should.equal(Error(term.InvalidBaseDirection("ltr ")))
}

pub fn base_direction_to_string_is_lowercase_test() {
  term.base_direction_to_string(term.LeftToRight) |> should.equal("ltr")
  term.base_direction_to_string(term.RightToLeft) |> should.equal("rtl")
}

pub fn directional_language_literal_constructor_test() {
  term.directional_language_literal("Hello", lang("en"), term.LeftToRight)
  |> should.equal(term.DirectionalLanguageTaggedLiteral(
    "Hello",
    lang("en"),
    term.LeftToRight,
  ))
}

pub fn directional_language_literal_from_strings_test() {
  term.directional_language_literal_from_strings("שלום", "HE", "rtl")
  |> should.equal(
    Ok(term.DirectionalLanguageTaggedLiteral(
      "שלום",
      lang("he"),
      term.RightToLeft,
    )),
  )
  term.directional_language_literal_from_strings("x", "en", "up")
  |> should.equal(Error(term.InvalidBaseDirection("up")))
  term.directional_language_literal_from_strings("x", "en", "LTR")
  |> should.equal(Error(term.InvalidBaseDirection("LTR")))
  term.directional_language_literal_from_strings("x", "", "ltr")
  |> should.equal(Error(term.InvalidLanguageTag("")))
}

pub fn directional_literal_differs_from_language_literal_test() {
  let plain = term.language_literal("x", lang("en"))
  let ltr = dir_literal("x", "en", term.LeftToRight)
  let rtl = dir_literal("x", "en", term.RightToLeft)
  { plain == ltr } |> should.be_false
  { ltr == rtl } |> should.be_false
}

pub fn facade_directional_language_literal_test() {
  let assert Ok(tag) = glaph_rdf.language_tag("ar")
  let assert Ok(direction) = glaph_rdf.base_direction("rtl")
  glaph_rdf.directional_language_literal("مرحبا", tag, direction)
  |> should.equal(term.DirectionalLanguageTaggedLiteral(
    "مرحبا",
    lang("ar"),
    term.RightToLeft,
  ))
  glaph_rdf.base_direction("sideways")
  |> should.equal(Error(term.InvalidBaseDirection("sideways")))
}

// N-Triples ---------------------------------------------------------------------

pub fn ntriples_parses_ltr_test() {
  nt_object("<http://ex.org/s> <http://ex.org/p> \"Hello\"@en--ltr .")
  |> should.equal(
    term.ObjectLiteral(dir_literal("Hello", "en", term.LeftToRight)),
  )
}

pub fn ntriples_parses_rtl_with_subtags_test() {
  nt_object("<http://ex.org/s> <http://ex.org/p> \"مرحبا\"@ar-EG--rtl .")
  |> should.equal(
    term.ObjectLiteral(dir_literal("مرحبا", "ar-eg", term.RightToLeft)),
  )
}

/// The language tag stays case-insensitive; only the direction is exact.
pub fn ntriples_parses_uppercase_tag_with_lowercase_dir_test() {
  nt_object("<http://ex.org/s> <http://ex.org/p> \"x\"@EN-US--ltr .")
  |> should.equal(
    term.ObjectLiteral(dir_literal("x", "en-us", term.LeftToRight)),
  )
}

/// W3C ntriples-langdir-bad-2 ("upper case LTR").
pub fn ntriples_rejects_uppercase_direction_test() {
  let line = fn(suffix) {
    "<http://example/a> <http://example/b> \"Hello\"@" <> suffix <> " ."
  }
  nt_error(line("en--LTR"))
  |> should.equal(
    "Invalid base direction 'LTR' in @en--LTR (expected ltr or rtl)",
  )
  string.contains(nt_error(line("EN-US--Rtl")), "Invalid base direction 'Rtl'")
  |> should.be_true
}

/// W3C ntriples-langdir-bad-3 / -bad-5: a language-tagged datatype written
/// with `^^` has no language tag (and no direction), so it is ill-formed.
/// It used to be read as an ordinary typed literal and written back out.
pub fn ntriples_rejects_lang_string_datatypes_test() {
  let line = fn(local) {
    "<http://example/a> <http://example/b> \"Hello\"^^<http://www.w3.org/1999/02/22-rdf-syntax-ns#"
    <> local
    <> "> ."
  }
  string.contains(nt_error(line("dirLangString")), "rdf:dirLangString")
  |> should.be_true
  string.contains(nt_error(line("langString")), "rdf:langString")
  |> should.be_true
  // Inside a triple term too.
  string.contains(
    nt_error(
      "<http://ex.org/s> <http://ex.org/p> <<( <http://ex.org/s> <http://ex.org/p> \"x\"^^<http://www.w3.org/1999/02/22-rdf-syntax-ns#dirLangString> )>> .",
    ),
    "rdf:dirLangString",
  )
  |> should.be_true
  // Other rdf: datatypes are unaffected.
  nt_object(
    "<http://ex.org/s> <http://ex.org/p> \"<b/>\"^^<http://www.w3.org/1999/02/22-rdf-syntax-ns#XMLLiteral> .",
  )
  |> should.equal(
    term.ObjectLiteral(term.typed_literal(
      "<b/>",
      iri("http://www.w3.org/1999/02/22-rdf-syntax-ns#XMLLiteral"),
    )),
  )
}

pub fn ntriples_non_directional_language_tag_unchanged_test() {
  nt_object("<http://ex.org/s> <http://ex.org/p> \"x\"@en-us .")
  |> should.equal(term.ObjectLiteral(term.language_literal("x", lang("en-us"))))
}

pub fn ntriples_parses_lang_dir_without_space_before_dot_test() {
  nt_object("<http://ex.org/s> <http://ex.org/p> \"x\"@en--rtl.")
  |> should.equal(term.ObjectLiteral(dir_literal("x", "en", term.RightToLeft)))
}

pub fn ntriples_serializes_ltr_and_rtl_test() {
  let ltr =
    statement.Triple(
      s(),
      p(),
      term.ObjectLiteral(dir_literal("Hello", "en-US", term.LeftToRight)),
    )
  let rtl =
    statement.Triple(
      s(),
      p(),
      term.ObjectLiteral(dir_literal("مرحبا", "ar", term.RightToLeft)),
    )
  ntriples.serialize_graph(graph.from_list([ltr]))
  |> should.equal(
    "<http://ex.org/s> <http://ex.org/p> \"Hello\"@en-us--ltr .\n",
  )
  ntriples.serialize_graph(graph.from_list([rtl]))
  |> should.equal("<http://ex.org/s> <http://ex.org/p> \"مرحبا\"@ar--rtl .\n")
}

pub fn ntriples_round_trip_keeps_direction_test() {
  let text =
    "<http://ex.org/s> <http://ex.org/p> \"a\"@en--ltr .\n"
    <> "<http://ex.org/s> <http://ex.org/p> \"a\"@en--rtl .\n"
    <> "<http://ex.org/s> <http://ex.org/p> \"a\"@en .\n"
  let assert Ok(doc) = ntriples.parse(text)
  graph.size(doc.graph) |> should.equal(3)
  let assert Ok(again) = ntriples.parse(ntriples.serialize(doc))
  again.graph |> should.equal(doc.graph)
  ntriples.serialize(again) |> should.equal(text)
}

pub fn ntriples_lang_dir_inside_triple_term_test() {
  let inner =
    term.triple_term(
      s(),
      p(),
      term.ObjectLiteral(dir_literal("x", "fr", term.RightToLeft)),
    )
  let text =
    "<<( <http://ex.org/s> <http://ex.org/p> \"x\"@fr--rtl )>> "
    <> "<http://ex.org/p> \"y\"@en--ltr ."
  let assert Ok(doc) = ntriples.parse(text)
  let assert [triple] = graph.triples(doc.graph)
  triple.subject |> should.equal(term.SubjectTriple(inner))
  triple.object
  |> should.equal(term.ObjectLiteral(dir_literal("y", "en", term.LeftToRight)))
  ntriples.serialize(doc) |> should.equal(text <> "\n")

  nt_object(
    "<http://ex.org/s> <http://ex.org/p> << <http://ex.org/s> <http://ex.org/p> \"x\"@fr--rtl >> .",
  )
  |> should.equal(term.ObjectTriple(inner))
}

pub fn ntriples_rejects_unknown_direction_test() {
  let message = nt_error("<http://ex.org/s> <http://ex.org/p> \"x\"@en--up .")
  string.contains(message, "Invalid base direction 'up'") |> should.be_true
  string.contains(message, "ltr or rtl") |> should.be_true
}

pub fn ntriples_rejects_malformed_lang_dir_test() {
  let line = fn(suffix) {
    "<http://ex.org/s> <http://ex.org/p> \"x\"@" <> suffix <> " ."
  }
  string.contains(nt_error(line("en--")), "Invalid base direction")
  |> should.be_true
  string.contains(nt_error(line("--ltr")), "Missing language tag")
  |> should.be_true
  string.contains(nt_error(line("en---ltr")), "Invalid base direction")
  |> should.be_true
  string.contains(nt_error(line("en--ltr--rtl")), "Invalid base direction")
  |> should.be_true
  string.contains(nt_error(line("en--ltr-x")), "Invalid base direction")
  |> should.be_true
}

pub fn ntriples_rejects_bad_lang_dir_inside_triple_term_test() {
  let message =
    nt_error(
      "<http://ex.org/s> <http://ex.org/p> <<( <http://ex.org/s> <http://ex.org/p> \"x\"@en--up )>> .",
    )
  string.contains(message, "Invalid base direction") |> should.be_true
}

// N-Quads -----------------------------------------------------------------------

pub fn nquads_parses_lang_dir_with_graph_label_test() {
  nq_single(
    "<http://ex.org/s> <http://ex.org/p> \"x\"@en--rtl <http://ex.org/g> .",
  )
  |> should.equal(statement.Quad(
    s(),
    p(),
    term.ObjectLiteral(dir_literal("x", "en", term.RightToLeft)),
    g(),
  ))
  nq_single("<http://ex.org/s> <http://ex.org/p> \"x\"@en--ltr .").object
  |> should.equal(term.ObjectLiteral(dir_literal("x", "en", term.LeftToRight)))
}

pub fn nquads_serializes_and_round_trips_test() {
  let quads = [
    statement.Quad(
      s(),
      p(),
      term.ObjectLiteral(dir_literal("a", "en", term.LeftToRight)),
      g(),
    ),
    statement.Quad(
      s(),
      p(),
      term.ObjectLiteral(dir_literal("a", "en", term.RightToLeft)),
      term.DefaultGraph,
    ),
  ]
  let ds = dataset.from_list(quads)
  let text = nquads.serialize_dataset(ds)
  string.contains(
    text,
    "<http://ex.org/s> <http://ex.org/p> \"a\"@en--ltr <http://ex.org/g> .",
  )
  |> should.be_true
  string.contains(text, "<http://ex.org/s> <http://ex.org/p> \"a\"@en--rtl .")
  |> should.be_true
  let assert Ok(parsed) = nquads.parse_dataset(text)
  dataset.quad_count(parsed) |> should.equal(2)
  list.sort(dataset.quads(parsed), fn(a, b) {
    string.compare(string.inspect(a), string.inspect(b))
  })
  |> should.equal(
    list.sort(quads, fn(a, b) {
      string.compare(string.inspect(a), string.inspect(b))
    }),
  )
}

pub fn nquads_lang_dir_inside_triple_term_test() {
  let text =
    "_:b <http://ex.org/p> <<( <http://ex.org/s> <http://ex.org/p> \"x\"@ar--rtl )>> <http://ex.org/g> ."
  let quad = nq_single(text)
  quad.object
  |> should.equal(
    term.ObjectTriple(term.triple_term(
      s(),
      p(),
      term.ObjectLiteral(dir_literal("x", "ar", term.RightToLeft)),
    )),
  )
  let assert Ok(doc) = nquads.parse(text)
  nquads.serialize(doc) |> should.equal(text <> "\n")
}

pub fn nquads_rejects_bad_lang_dir_test() {
  let line = fn(suffix) {
    "<http://ex.org/s> <http://ex.org/p> \"x\"@"
    <> suffix
    <> " <http://ex.org/g> ."
  }
  string.contains(nq_error(line("en--up")), "Invalid base direction 'up'")
  |> should.be_true
  string.contains(nq_error(line("en--")), "Invalid base direction")
  |> should.be_true
  string.contains(nq_error(line("--ltr")), "Missing language tag")
  |> should.be_true
  string.contains(nq_error(line("en---ltr")), "Invalid base direction")
  |> should.be_true
}

/// W3C nquads-langdir-bad-2 ("upper case LTR") and the N-Quads form of
/// ntriples-langdir-bad-5.
pub fn nquads_rejects_uppercase_direction_and_dir_lang_string_test() {
  nq_error(
    "<http://example/a> <http://example/b> \"Hello\"@en--LTR <http://example/g> .",
  )
  |> should.equal(
    "Invalid base direction 'LTR' in @en--LTR (expected ltr or rtl)",
  )
  string.contains(
    nq_error(
      "<http://example/a> <http://example/b> \"Hello\"^^<http://www.w3.org/1999/02/22-rdf-syntax-ns#dirLangString> <http://example/g> .",
    ),
    "rdf:dirLangString",
  )
  |> should.be_true
}

// Streaming file round trip -------------------------------------------------------

pub fn ntriples_streaming_file_round_trip_test() {
  let rdf_graph =
    graph.from_list([
      statement.Triple(
        s(),
        p(),
        term.ObjectLiteral(dir_literal("Hello", "en", term.LeftToRight)),
      ),
      statement.Triple(
        s(),
        p(),
        term.ObjectLiteral(dir_literal("مرحبا", "ar", term.RightToLeft)),
      ),
    ])
  let #(streamed, loaded) =
    with_path("nt", fn(path) {
      let assert Ok(Nil) = ntriples.streaming_serialize_to_file(rdf_graph, path)
      #(ntriples.streaming_parse_file(path), ntriples.parse_file(path))
    })
  let assert Ok(streamed) = streamed
  let assert Ok(loaded) = loaded
  graph.isomorphic(streamed.graph, rdf_graph) |> should.be_true
  graph.isomorphic(loaded.graph, rdf_graph) |> should.be_true
}

pub fn nquads_streaming_file_round_trip_test() {
  let ds =
    dataset.from_list([
      statement.Quad(
        s(),
        p(),
        term.ObjectLiteral(dir_literal("x", "he", term.RightToLeft)),
        g(),
      ),
      statement.Quad(
        s(),
        p(),
        term.ObjectLiteral(dir_literal("x", "he", term.LeftToRight)),
        term.DefaultGraph,
      ),
    ])
  let #(streamed, loaded) =
    with_path("nq", fn(path) {
      let assert Ok(Nil) = nquads.streaming_serialize_to_file(ds, path)
      #(nquads.streaming_parse_file(path), nquads.parse_file(path))
    })
  let assert Ok(streamed) = streamed
  let assert Ok(loaded) = loaded
  dataset.isomorphic(streamed.dataset, ds) |> should.be_true
  dataset.isomorphic(loaded.dataset, ds) |> should.be_true
}

// Isomorphism -------------------------------------------------------------------

fn blank_triple(id: String, literal: term.Literal) -> statement.Triple {
  statement.Triple(
    term.SubjectBlank(term.BlankNode(id)),
    p(),
    term.ObjectLiteral(literal),
  )
}

pub fn graph_isomorphism_distinguishes_direction_test() {
  let ltr =
    graph.from_list([
      blank_triple("a", dir_literal("x", "en", term.LeftToRight)),
    ])
  let ltr2 =
    graph.from_list([
      blank_triple("b", dir_literal("x", "en", term.LeftToRight)),
    ])
  let rtl =
    graph.from_list([
      blank_triple("b", dir_literal("x", "en", term.RightToLeft)),
    ])
  let plain =
    graph.from_list([blank_triple("b", term.language_literal("x", lang("en")))])
  graph.isomorphic(ltr, ltr2) |> should.be_true
  graph.isomorphic(ltr, rtl) |> should.be_false
  graph.isomorphic(ltr, plain) |> should.be_false
  graph.isomorphic(rtl, plain) |> should.be_false
}

pub fn graph_keeps_directional_variants_distinct_test() {
  graph.from_list([
    blank_triple("a", dir_literal("x", "en", term.LeftToRight)),
    blank_triple("a", dir_literal("x", "en", term.RightToLeft)),
    blank_triple("a", term.language_literal("x", lang("en"))),
  ])
  |> graph.size
  |> should.equal(3)
}

pub fn canonicalize_keeps_direction_test() {
  let rdf_graph =
    graph.from_list([
      blank_triple("z", dir_literal("x", "en", term.RightToLeft)),
      blank_triple("y", dir_literal("x", "en", term.LeftToRight)),
    ])
  let canonical = graph.canonicalize(rdf_graph)
  graph.size(canonical) |> should.equal(2)
  graph.isomorphic(canonical, rdf_graph) |> should.be_true
}

pub fn dataset_isomorphism_distinguishes_direction_test() {
  let quad = fn(id, direction) {
    statement.Quad(
      term.SubjectBlank(term.BlankNode(id)),
      p(),
      term.ObjectLiteral(dir_literal("x", "en", direction)),
      term.BlankGraph(term.BlankNode("g" <> id)),
    )
  }
  let ltr = dataset.from_list([quad("a", term.LeftToRight)])
  let ltr2 = dataset.from_list([quad("b", term.LeftToRight)])
  let rtl = dataset.from_list([quad("b", term.RightToLeft)])
  dataset.isomorphic(ltr, ltr2) |> should.be_true
  dataset.isomorphic(ltr, rtl) |> should.be_false
}

// Canonical N-Triples: lowercase LANG_DIR --------------------------------------
//
// RDF 1.2 N-Triples section 3: "Alphabetic characters in LANG_DIR MUST use
// only the lowercase letters ([a-z])". `term.language_tag` stores BCP 47
// display case (`en-GB`), which the N-Triples / N-Quads writers printed
// verbatim. W3C rdf12 c14n test `dirlangtagged_string` expects `@en-gb--ltr`.

const c14n_subject = "<http://a.example/s> <http://a.example/p> "

pub fn language_tag_doc_examples_test() {
  term.language_tag("en-US") |> should.equal(Ok(term.LanguageTag("en-US")))
  term.language_tag("en-us") |> should.equal(Ok(term.LanguageTag("en-US")))
  term.language_tag("ZH-HANT") |> should.equal(Ok(term.LanguageTag("zh-Hant")))
  term.language_tag("en--x")
  |> should.equal(Error(term.InvalidLanguageTag("en--x")))
}

pub fn ntriples_c14n_dirlangtagged_string_test() {
  let assert Ok(doc) = ntriples.parse(c14n_subject <> "\"chat\"@EN-GB--ltr .")
  ntriples.serialize(doc)
  |> should.equal(c14n_subject <> "\"chat\"@en-gb--ltr .\n")
}

pub fn ntriples_c14n_langtagged_string_test() {
  let assert Ok(doc) = ntriples.parse(c14n_subject <> "\"chat\"@EN-GB .")
  ntriples.serialize(doc)
  |> should.equal(c14n_subject <> "\"chat\"@en-gb .\n")
}

fn mixed_case_objects() -> List(term.Object) {
  [
    term.ObjectLiteral(term.language_literal("colour", lang("en-GB"))),
    term.ObjectLiteral(term.language_literal("x", lang("zh-Hant-TW"))),
    term.ObjectLiteral(dir_literal("chat", "en-GB", term.LeftToRight)),
    term.ObjectLiteral(dir_literal("مرحبا", "ar-EG", term.RightToLeft)),
    term.ObjectTriple(term.triple_term(
      s(),
      p(),
      term.ObjectLiteral(dir_literal("y", "sr-Latn-RS", term.RightToLeft)),
    )),
  ]
}

fn mixed_case_graph() -> graph.Graph {
  mixed_case_objects()
  |> list.map(fn(object) { statement.Triple(s(), p(), object) })
  |> graph.from_list
}

fn mixed_case_dataset() -> dataset.Dataset {
  mixed_case_objects()
  |> list.flat_map(fn(object) {
    [
      statement.Quad(s(), p(), object, g()),
      statement.Quad(s(), p(), object, term.DefaultGraph),
    ]
  })
  |> dataset.from_list
}

/// Every `@...` suffix in canonical output is lowercase. The fixture has no
/// uppercase outside language tags, so lowercasing the whole text must be a
/// no-op once the tags are canonical.
fn assert_lowercase_lang_dir(text: String) -> Nil {
  text |> should.equal(string.lowercase(text))
  text |> string.contains("@en-gb") |> should.be_true
  text |> string.contains("@en-gb--ltr") |> should.be_true
  text |> string.contains("@zh-hant-tw") |> should.be_true
  text |> string.contains("@ar-eg--rtl") |> should.be_true
  text |> string.contains("@sr-latn-rs--rtl") |> should.be_true
  text |> string.contains("GB") |> should.be_false
  text |> string.contains("Hant") |> should.be_false
  text |> string.contains("Latn") |> should.be_false
}

pub fn parsing_lowercase_tag_equals_display_case_tag_test() {
  let assert Ok(doc) = ntriples.parse(c14n_subject <> "\"chat\"@en-gb--ltr .")
  let assert [triple] = graph.triples(doc.graph)
  triple.object
  |> should.equal(
    term.ObjectLiteral(dir_literal("chat", "en-GB", term.LeftToRight)),
  )
  nt_object(c14n_subject <> "\"x\"@zh-hant-tw .")
  |> should.equal(
    term.ObjectLiteral(term.language_literal("x", lang("zh-Hant-TW"))),
  )
}

pub fn ntriples_lowercase_lang_dir_round_trips_test() {
  let original = mixed_case_graph()
  let text = ntriples.serialize_graph(original)
  assert_lowercase_lang_dir(text)
  let assert Ok(reparsed) = ntriples.parse_graph(text)
  reparsed |> should.equal(original)
  ntriples.serialize_graph(reparsed) |> should.equal(text)
}

pub fn nquads_lowercase_lang_dir_round_trips_test() {
  let original = mixed_case_dataset()
  let text = nquads.serialize_dataset(original)
  assert_lowercase_lang_dir(text)
  let assert Ok(reparsed) = nquads.parse_dataset(text)
  reparsed |> should.equal(original)
  nquads.serialize_dataset(reparsed) |> should.equal(text)
}

pub fn ntriples_streaming_writer_lowercase_lang_dir_test() {
  let original = mixed_case_graph()
  let #(written, content, reparsed) =
    with_path("nt_lowercase.nt", fn(path) {
      let written = ntriples.streaming_serialize_to_file(original, path)
      #(written, simplifile.read(path), ntriples.streaming_parse_file(path))
    })
  written |> should.equal(Ok(Nil))
  let assert Ok(text) = content
  assert_lowercase_lang_dir(text)
  text |> should.equal(ntriples.serialize_graph(original))
  reparsed |> should.equal(Ok(ntriples.NTriplesDocument(graph: original)))
}

pub fn nquads_streaming_writer_lowercase_lang_dir_test() {
  let original = mixed_case_dataset()
  let #(written, content, reparsed) =
    with_path("nq_lowercase.nq", fn(path) {
      let written = nquads.streaming_serialize_to_file(original, path)
      #(written, simplifile.read(path), nquads.streaming_parse_file(path))
    })
  written |> should.equal(Ok(Nil))
  let assert Ok(text) = content
  assert_lowercase_lang_dir(text)
  text |> should.equal(nquads.serialize_dataset(original))
  reparsed |> should.equal(Ok(nquads.NQuadsDocument(dataset: original)))
}

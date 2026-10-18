//// Regression tests for the N-Triples / N-Quads review findings
//// (#3, #4, #5, #6, #7, #12, #15). Every test runs on both Erlang and
//// JavaScript.

import glaph_rdf/dataset
import glaph_rdf/graph
import glaph_rdf/serializers/nquads
import glaph_rdf/serializers/ntriples
import glaph_rdf/statement
import glaph_rdf/term
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

/// Parses N-Triples text that must contain exactly one triple.
fn nt_single(text: String) -> statement.Triple {
  let assert Ok(doc) = ntriples.parse(text)
  let assert [triple] = graph.triples(doc.graph)
  triple
}

/// Parses N-Quads text that must contain exactly one quad.
fn nq_single(text: String) -> statement.Quad {
  let assert Ok(doc) = nquads.parse(text)
  let assert [quad] = dataset.quads(doc.dataset)
  quad
}

fn nt_object(text: String) -> term.Object {
  nt_single(text).object
}

fn nq_object(text: String) -> term.Object {
  nq_single(text).object
}

fn sorted_lines(text: String) -> List(String) {
  string.split(text, "\n") |> list.sort(string.compare)
}

fn nt_round_trip(triples: List(statement.Triple)) -> Nil {
  let text = ntriples.serialize_graph(graph.from_list(triples))
  let assert Ok(doc) = ntriples.parse(text)
  let parsed = graph.triples(doc.graph)
  list.length(parsed) |> should.equal(list.length(triples))
  list.each(triples, fn(t) { list.contains(parsed, t) |> should.be_true })
}

fn nq_round_trip(quads: List(statement.Quad)) -> Nil {
  let text = nquads.serialize_dataset(dataset.from_list(quads))
  let assert Ok(doc) = nquads.parse(text)
  let parsed = dataset.quads(doc.dataset)
  list.length(parsed) |> should.equal(list.length(quads))
  list.each(quads, fn(q) { list.contains(parsed, q) |> should.be_true })
}

const nasty =
  "C:\\new\\table \\\\ \"quoted\" it's\nline2\r\ttab \u{0008}\u{000C} \u{0001}\u{001F}\u{007F} café 日本語 😀 # not a comment"

// #3: non-ASCII content must not shift @lang / ^^datatype / quoted triples ------

pub fn non_ascii_language_literal_test() {
  let text = "<http://ex.org/s> <http://ex.org/p> \"café\"@fr ."
  nt_object(text)
  |> should.equal(term.ObjectLiteral(term.language_literal("café", lang("fr"))))
  nq_object(text)
  |> should.equal(term.ObjectLiteral(term.language_literal("café", lang("fr"))))

  let cjk = "<http://ex.org/s> <http://ex.org/p> \"日本語\"@ja <http://ex.org/g> ."
  nq_object(cjk)
  |> should.equal(term.ObjectLiteral(term.language_literal("日本語", lang("ja"))))
  nq_single(cjk).graph |> should.equal(g())
}

pub fn non_ascii_typed_literal_test() {
  let dt = iri("http://www.w3.org/2001/XMLSchema#string")
  let text =
    "<http://ex.org/s> <http://ex.org/p> \"żółć 😀\"^^<http://www.w3.org/2001/XMLSchema#string> ."
  nt_object(text)
  |> should.equal(term.ObjectLiteral(term.typed_literal("żółć 😀", dt)))
  nq_object(text)
  |> should.equal(term.ObjectLiteral(term.typed_literal("żółć 😀", dt)))
}

pub fn non_ascii_quoted_triple_subject_test() {
  let text =
    "<<( <http://ex.org/é> <http://ex.org/p> \"naïve\"@fr )>> <http://ex.org/q> \"Ωmega\" ."
  let expected_subject =
    term.SubjectTriple(term.triple_term(
      term.SubjectNamed(iri("http://ex.org/é")),
      p(),
      term.ObjectLiteral(term.language_literal("naïve", lang("fr"))),
    ))
  let triple = nt_single(text)
  triple.subject |> should.equal(expected_subject)
  triple.object
  |> should.equal(term.ObjectLiteral(term.simple_literal("Ωmega")))

  let quad = nq_single(text)
  quad.subject |> should.equal(expected_subject)
  quad.object |> should.equal(term.ObjectLiteral(term.simple_literal("Ωmega")))
}

// #4: one left-to-right escape decoder (ECHAR + UCHAR) ------------------------

pub fn escaped_backslash_before_letter_test() {
  // Written form: "C:\\new\\table"  ->  value C:\new\table
  nt_object("<http://ex.org/s> <http://ex.org/p> \"C:\\\\new\\\\table\" .")
  |> should.equal(term.ObjectLiteral(term.simple_literal("C:\\new\\table")))
  // \\" is an escaped backslash followed by the closing quote
  nt_object("<http://ex.org/s> <http://ex.org/p> \"end\\\\\" .")
  |> should.equal(term.ObjectLiteral(term.simple_literal("end\\")))
}

pub fn all_echar_escapes_test() {
  nt_object(
    "<http://ex.org/s> <http://ex.org/p> \"\\t\\b\\n\\r\\f\\\"\\'\\\\\" .",
  )
  |> should.equal(
    term.ObjectLiteral(term.simple_literal("\t\u{0008}\n\r\u{000C}\"'\\")),
  )
}

pub fn uchar_escapes_in_literals_and_iris_test() {
  let triple =
    nt_single(
      "<http://ex.org/caf\\u00E9> <http://ex.org/p> \"caf\\u00e9 \\U0001F600\" .",
    )
  triple.subject |> should.equal(term.SubjectNamed(iri("http://ex.org/café")))
  triple.object
  |> should.equal(term.ObjectLiteral(term.simple_literal("café 😀")))
}

pub fn invalid_escapes_are_errors_test() {
  ntriples.parse("<http://ex.org/s> <http://ex.org/p> \"bad \\q\" .")
  |> should.be_error
  ntriples.parse("<http://ex.org/s> <http://ex.org/p> \"bad \\u00ZZ\" .")
  |> should.be_error
  ntriples.parse("<http://ex.org/s> <http://ex.org/p> \"short \\u12\" .")
  |> should.be_error
  // Surrogate code points are not characters
  ntriples.parse("<http://ex.org/s> <http://ex.org/p> \"\\uD800\" .")
  |> should.be_error
  // ECHAR is not allowed in IRIs
  ntriples.parse("<http://ex.org/a\\nb> <http://ex.org/p> \"o\" .")
  |> should.be_error
  nquads.parse("<http://ex.org/s> <http://ex.org/p> \"bad \\q\" .")
  |> should.be_error
}

pub fn escape_string_exact_output_test() {
  let text =
    ntriples.serialize_graph(
      graph.from_list([
        statement.Triple(
          s(),
          p(),
          term.ObjectLiteral(term.simple_literal(
            "a\\b\"c\nd\re\tf\u{0001}g\u{007F}h é",
          )),
        ),
      ]),
    )
  text
  |> should.equal(
    "<http://ex.org/s> <http://ex.org/p> \"a\\\\b\\\"c\\nd\\re\\tf\\u0001g\\u007Fh é\" .\n",
  )
}

pub fn ntriples_round_trip_nasty_literals_test() {
  nt_round_trip([
    statement.Triple(s(), p(), term.ObjectLiteral(term.simple_literal(nasty))),
    statement.Triple(
      s(),
      iri("http://ex.org/p2"),
      term.ObjectLiteral(term.language_literal(nasty, lang("en"))),
    ),
    statement.Triple(
      s(),
      iri("http://ex.org/p3"),
      term.ObjectLiteral(term.typed_literal(nasty, iri("http://ex.org/dt"))),
    ),
  ])
}

pub fn iri_escaping_is_consistent_with_decoder_test() {
  // unsafe_named_node can hold characters IRIREF forbids; the writer must
  // emit them as \u escapes (never raw), and the decoder must recover them
  // exactly.
  let odd = term.unsafe_named_node("http://ex.org/a{b}|c^d`e")
  let text =
    ntriples.serialize_graph(
      graph.from_list([statement.Triple(s(), p(), term.ObjectNamed(odd))]),
    )
  text
  |> should.equal(
    "<http://ex.org/s> <http://ex.org/p> <http://ex.org/a\\u007Bb\\u007D\\u007Cc\\u005Ed\\u0060e> .\n",
  )
  // term.named_node validation differs per target (Erlang rejects these
  // characters, JavaScript accepts them); either way the decoded IRI must be
  // exactly the original string.
  case ntriples.parse(text) {
    Ok(doc) ->
      graph.triples(doc.graph)
      |> should.equal([statement.Triple(s(), p(), term.ObjectNamed(odd))])
    Error(ntriples.NTriplesError(message, line)) -> {
      line |> should.equal(1)
      message |> should.equal("Invalid IRI: http://ex.org/a{b}|c^d`e")
    }
  }
}

// #5: N-Quads decodes escapes exactly like N-Triples --------------------------

pub fn nquads_unescapes_literals_test() {
  nq_object(
    "<http://ex.org/s> <http://ex.org/p> \"a\\\"b\" <http://ex.org/g> .",
  )
  |> should.equal(term.ObjectLiteral(term.simple_literal("a\"b")))
  nq_object("<http://ex.org/s> <http://ex.org/p> \"C:\\\\dir\\nx\" .")
  |> should.equal(term.ObjectLiteral(term.simple_literal("C:\\dir\nx")))
}

pub fn nquads_round_trip_nasty_literals_test() {
  let quads = [
    statement.Quad(
      s(),
      p(),
      term.ObjectLiteral(term.simple_literal(nasty)),
      term.DefaultGraph,
    ),
    statement.Quad(
      s(),
      p(),
      term.ObjectLiteral(term.simple_literal(nasty)),
      g(),
    ),
    statement.Quad(
      s(),
      p(),
      term.ObjectLiteral(term.language_literal(nasty, lang("en-GB"))),
      term.BlankGraph(term.unsafe_blank_node("g1")),
    ),
  ]
  nq_round_trip(quads)

  // Repeated round trips must be stable (no escape layer added per pass)
  let once = nquads.serialize_dataset(dataset.from_list(quads))
  let assert Ok(doc) = nquads.parse(once)
  sorted_lines(nquads.serialize_dataset(doc.dataset))
  |> should.equal(sorted_lines(once))
}

// #6: quote / IRI / triple-term aware tokenizer for N-Quads -------------------

pub fn nquads_literal_with_spaces_test() {
  let plain = term.ObjectLiteral(term.simple_literal("hello world"))
  nq_object("<http://ex.org/s> <http://ex.org/p> \"hello world\" .")
  |> should.equal(plain)
  let quad =
    nq_single(
      "<http://ex.org/s> <http://ex.org/p> \"hello world\" <http://ex.org/g> .",
    )
  quad.object |> should.equal(plain)
  quad.graph |> should.equal(g())
}

pub fn nquads_literal_with_escaped_quotes_and_suffixes_test() {
  let lang_quad =
    nq_single(
      "<http://ex.org/s> <http://ex.org/p> \"say \\\"hi there\\\" now\"@en-US <http://ex.org/g> .",
    )
  lang_quad.object
  |> should.equal(
    term.ObjectLiteral(term.language_literal(
      "say \"hi there\" now",
      lang("en-US"),
    )),
  )
  lang_quad.graph |> should.equal(g())

  let typed =
    nq_object(
      "<http://ex.org/s> <http://ex.org/p> \"a b . c\"^^<http://ex.org/dt> .",
    )
  typed
  |> should.equal(
    term.ObjectLiteral(term.typed_literal("a b . c", iri("http://ex.org/dt"))),
  )

  let typed_graph =
    nq_single(
      "<http://ex.org/s> <http://ex.org/p> \"a b\"^^<http://ex.org/dt> _:g1 .",
    )
  typed_graph.graph
  |> should.equal(term.BlankGraph(term.unsafe_blank_node("g1")))
}

pub fn nquads_tabs_and_no_space_before_dot_test() {
  let quad =
    nq_single(
      "<http://ex.org/s>\t<http://ex.org/p>\t\"x y\"\t<http://ex.org/g>.",
    )
  quad.object |> should.equal(term.ObjectLiteral(term.simple_literal("x y")))
  quad.graph |> should.equal(g())
}

pub fn nquads_too_many_terms_is_error_test() {
  nquads.parse(
    "<http://ex.org/s> <http://ex.org/p> \"o\" <http://ex.org/g> <http://ex.org/h> .",
  )
  |> should.be_error
}

pub fn ntriples_rejects_graph_label_test() {
  ntriples.parse(
    "<http://ex.org/s> <http://ex.org/p> \"o\" <http://ex.org/g> .",
  )
  |> should.be_error
}

// #7: N-Quads writes and reads triple terms -----------------------------------

pub fn nquads_serializes_triple_terms_test() {
  let inner =
    term.triple_term(s(), p(), term.ObjectLiteral(term.simple_literal("o")))
  let quad =
    statement.Quad(
      term.SubjectTriple(inner),
      iri("http://ex.org/q"),
      term.ObjectNamed(iri("http://ex.org/x")),
      g(),
    )
  let text = nquads.serialize_dataset(dataset.from_list([quad]))
  text
  |> should.equal(
    "<<( <http://ex.org/s> <http://ex.org/p> \"o\" )>> <http://ex.org/q> <http://ex.org/x> <http://ex.org/g> .\n",
  )
  string.contains(text, "not-implemented") |> should.be_false
}

pub fn nquads_round_trip_triple_terms_test() {
  let inner =
    term.triple_term(
      term.SubjectBlank(term.unsafe_blank_node("b1")),
      p(),
      term.ObjectLiteral(term.simple_literal("with space )>> and \"quote\"")),
    )
  let nested =
    term.triple_term(
      term.SubjectTriple(inner),
      iri("http://ex.org/q"),
      term.ObjectTriple(inner),
    )
  let q = iri("http://ex.org/q")
  nq_round_trip([
    statement.Quad(
      term.SubjectTriple(inner),
      q,
      term.ObjectNamed(iri("http://ex.org/x")),
      term.DefaultGraph,
    ),
    statement.Quad(term.SubjectTriple(inner), q, term.ObjectTriple(inner), g()),
    statement.Quad(s(), q, term.ObjectTriple(inner), term.DefaultGraph),
    statement.Quad(s(), q, term.ObjectTriple(nested), g()),
    statement.Quad(
      term.SubjectTriple(nested),
      q,
      term.ObjectTriple(nested),
      g(),
    ),
  ])
}

pub fn nquads_reads_legacy_rdf_star_syntax_test() {
  let quad =
    nq_single(
      "<< <http://ex.org/s> <http://ex.org/p> \"o\" >> <http://ex.org/q> \"v\" <http://ex.org/g> .",
    )
  quad.subject
  |> should.equal(
    term.SubjectTriple(term.triple_term(
      s(),
      p(),
      term.ObjectLiteral(term.simple_literal("o")),
    )),
  )
  quad.graph |> should.equal(g())
}

// #12: comments are skipped everywhere; '#' inside terms is not a comment -----

const commented =
  "# generated by rdflib
   # indented comment

<http://ex.org/s> <http://ex.org/p#frag> \"has # hash\" . # trailing comment
<http://ex.org/s> <http://ex.org/p#frag> <http://ex.org/o#x>.# no space
"

pub fn ntriples_parse_skips_comments_test() {
  let assert Ok(doc) = ntriples.parse(commented)
  let triples = graph.triples(doc.graph)
  list.length(triples) |> should.equal(2)
  list.contains(
    triples,
    statement.Triple(
      s(),
      iri("http://ex.org/p#frag"),
      term.ObjectLiteral(term.simple_literal("has # hash")),
    ),
  )
  |> should.be_true
  list.contains(
    triples,
    statement.Triple(
      s(),
      iri("http://ex.org/p#frag"),
      term.ObjectNamed(iri("http://ex.org/o#x")),
    ),
  )
  |> should.be_true
}

pub fn nquads_parse_skips_comments_test() {
  let assert Ok(doc) = nquads.parse(commented)
  list.length(dataset.quads(doc.dataset)) |> should.equal(2)
  let quad =
    nq_single(
      "<http://ex.org/s> <http://ex.org/p> \"o\" <http://ex.org/g#1> . # c",
    )
  quad.graph
  |> should.equal(term.NamedGraph(iri("http://ex.org/g#1")))
}

pub fn ntriples_parse_file_skips_comments_test() {
  let path = "build/tmp_regression_core_comments.nt"
  let assert Ok(Nil) = simplifile.write(path, commented)
  let result = ntriples.parse_file(path)
  let _ = simplifile.delete(path)
  let assert Ok(doc) = result
  graph.size(doc.graph) |> should.equal(2)
}

pub fn content_after_final_dot_is_error_test() {
  ntriples.parse("<http://ex.org/s> <http://ex.org/p> \"o\" . junk")
  |> should.be_error
  nquads.parse("<http://ex.org/s> <http://ex.org/p> \"o\" . junk")
  |> should.be_error
}

pub fn error_line_numbers_count_comment_lines_test() {
  let text = "# c\n\n<http://ex.org/s> <http://ex.org/p> \"o\"\n"
  let assert Error(ntriples.NTriplesError(_, line)) = ntriples.parse(text)
  line |> should.equal(3)
  let assert Error(nquads.NQuadsError(_, line)) = nquads.parse(text)
  line |> should.equal(3)
}

// #15: both N-Quads writers produce identical canonical bytes ---------------

pub fn nquads_writers_produce_identical_bytes_test() {
  let default_quad =
    statement.Quad(
      s(),
      p(),
      term.ObjectNamed(iri("http://ex.org/o")),
      term.DefaultGraph,
    )
  let named_quad =
    statement.Quad(s(), p(), term.ObjectLiteral(term.simple_literal("v")), g())

  let default_line = "<http://ex.org/s> <http://ex.org/p> <http://ex.org/o> .\n"
  let named_line =
    "<http://ex.org/s> <http://ex.org/p> \"v\" <http://ex.org/g> .\n"

  nquads.serialize_dataset(dataset.from_list([default_quad]))
  |> should.equal(default_line)
  nquads.serialize_dataset(dataset.from_list([named_quad]))
  |> should.equal(named_line)

  let path = "build/tmp_regression_core_writers.nq"
  let assert Ok(Nil) =
    nquads.streaming_serialize_to_file(dataset.from_list([default_quad]), path)
  let streamed_default = simplifile.read(path)
  let assert Ok(Nil) =
    nquads.streaming_serialize_to_file(dataset.from_list([named_quad]), path)
  let streamed_named = simplifile.read(path)
  let _ = simplifile.delete(path)

  streamed_default |> should.equal(Ok(default_line))
  streamed_named |> should.equal(Ok(named_line))
}

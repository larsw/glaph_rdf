//// Regression tests for prefixed-name compaction in the Turtle and TriG
//// writers, and for byte order marks in the string parse entry points.
////
//// - The writers compacted IRIs to prefixed names without checking that the
////   local part is a valid PN_LOCAL, so `http://ex.org/a/b` was written as
////   `ex:a/b`, which no Turtle parser (including ours) reads back. On
////   JavaScript only, a namespace boundary inside a grapheme cluster (a
////   combining accent) produced a local name starting with the accent.
//// - The Turtle lexer only knew ASCII names, so valid prefixed names with
////   escapes, percent sequences, dots, colons or non-ASCII characters could
////   not be read.
//// - The `@prefix` lines (and the tie-break between labels for the same
////   namespace) depended on dictionary order or `string.compare`, so output
////   differed between Erlang and JavaScript.
//// - `ntriples.parse` and `nquads.parse` failed on text starting with a byte
////   order mark, while the file readers stripped it.

import glaph_rdf/dataset
import glaph_rdf/graph
import glaph_rdf/serializers/nquads
import glaph_rdf/serializers/ntriples
import glaph_rdf/serializers/trig
import glaph_rdf/serializers/turtle
import glaph_rdf/statement
import glaph_rdf/term
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit/should
import simplifile

const ns = "http://ex.org/"

const bom = "\u{FEFF}"

/// Local parts that are awkward to write as PN_LOCAL. Each one becomes the
/// subject, object and datatype of a triple. All of them make valid IRIs
/// (characters such as a space cannot appear in an IRI at all, so they are
/// only checked for the `<IRI>` fallback).
const tricky_locals = [
  "a/b", "-x", "1abc", ".a", "a.", "a.b", "a..b", "a~b", "a#b", "a?b", "a@b",
  "a&b", "a;b", "a=b", "a,b", "a(b)", "a'b", "a!b", "a$b", "a*b", "a+b", "%41",
  "a%41b", "a%", "%", "%4", "%zz", "café", "日本語", "😀", "👍🏽", "\u{0301}x",
  "a\u{0301}", "a:b", ":a", "", "_a", "a_", "a-", "-", ".", "..", "a/", "/",
  "\u{00B7}a", "a\u{00B7}", "0", "a%2F", "a//b", "#", "a.%41.",
]

fn named(value: String) -> term.NamedNode {
  term.unsafe_named_node(value)
}

fn tricky_triples(locals: List(String)) -> List(statement.Triple) {
  list.flat_map(locals, fn(local) {
    let iri = named(ns <> local)
    [
      statement.Triple(
        subject: term.SubjectNamed(iri),
        predicate: named(ns <> "p"),
        object: term.ObjectNamed(iri),
      ),
      statement.Triple(
        subject: term.SubjectNamed(named(ns <> "s")),
        predicate: iri,
        object: term.ObjectLiteral(term.TypedLiteral("v", iri)),
      ),
    ]
  })
}

fn ex_prefixes() -> dict.Dict(String, String) {
  dict.from_list([#("ex", ns)])
}

fn same_graph(actual: graph.Graph, expected: graph.Graph) -> Bool {
  graph.size(actual) == graph.size(expected)
  && list.all(graph.triples(expected), graph.contains(actual, _))
}

fn turtle_text(triples: List(statement.Triple), prefixes) -> String {
  turtle.serialize_graph(graph.from_list(triples), None, prefixes)
}

fn one_iri_turtle(iri: String, prefixes) -> String {
  turtle_text(
    [
      statement.Triple(
        subject: term.SubjectNamed(named(iri)),
        predicate: named("http://other.org/p"),
        object: term.ObjectLiteral(term.SimpleLiteral("o")),
      ),
    ],
    prefixes,
  )
}

// PN_LOCAL escaping -----------------------------------------------------------

pub fn tricky_locals_are_valid_iris_test() {
  list.each(tricky_locals, fn(local) {
    let assert Ok(_) = term.named_node(ns <> local)
  })
}

pub fn turtle_tricky_local_names_round_trip_test() {
  list.each(tricky_locals, fn(local) {
    let original = graph.from_list(tricky_triples([local]))
    let text = turtle.serialize_graph(original, None, ex_prefixes())
    case turtle.parse_graph(text) {
      Ok(parsed) ->
        case same_graph(parsed, original) {
          True -> Nil
          False -> panic as { "Turtle round trip changed " <> text }
        }
      Error(turtle.TurtleError(message, _)) ->
        panic as { "Turtle round trip failed: " <> message <> "\n" <> text }
    }
  })
}

pub fn trig_tricky_local_names_round_trip_test() {
  list.each(tricky_locals, fn(local) {
    let original =
      dataset.new()
      |> dataset.replace_graph(
        term.DefaultGraph,
        graph.from_list(tricky_triples([local])),
      )
    let text = trig.serialize_dataset(original, None, ex_prefixes())
    case trig.parse_dataset(text) {
      Ok(parsed) ->
        case
          same_graph(
            dataset.default_graph(parsed),
            dataset.default_graph(original),
          )
          && dataset.quad_count(parsed) == dataset.quad_count(original)
        {
          True -> Nil
          False -> panic as { "TriG round trip changed " <> text }
        }
      Error(trig.TrigError(message, _)) ->
        panic as { "TriG round trip failed: " <> message <> "\n" <> text }
    }
  })
}

pub fn all_tricky_local_names_in_one_document_round_trip_test() {
  let original = graph.from_list(tricky_triples(tricky_locals))
  let text = turtle.serialize_graph(original, None, ex_prefixes())
  let assert Ok(parsed) = turtle.parse_graph(text)
  same_graph(parsed, original) |> should.be_true
}

pub fn turtle_escapes_local_names_exactly_test() {
  let cases = [
    #("a/b", "ex:a\\/b"),
    #("-x", "ex:\\-x"),
    #("a.", "ex:a\\."),
    #(".a", "ex:\\.a"),
    #("a.b", "ex:a.b"),
    #("a-", "ex:a-"),
    #("1abc", "ex:1abc"),
    #("a~b", "ex:a\\~b"),
    #("a#b", "ex:a\\#b"),
    #("%41", "ex:%41"),
    #("a%", "ex:a\\%"),
    #("%zz", "ex:\\%zz"),
    #("a:b", "ex:a:b"),
    #("", "ex:"),
    #("café", "ex:café"),
    #("😀", "ex:😀"),
    #("a b", "<http://ex.org/a\\u0020b>"),
    #("a|b", "<http://ex.org/a\\u007Cb>"),
    #("a{b", "<http://ex.org/a\\u007Bb>"),
    #("\u{0301}x", "<http://ex.org/\u{0301}x>"),
  ]
  list.each(cases, fn(pair) {
    let #(local, expected) = pair
    let text = one_iri_turtle(ns <> local, ex_prefixes())
    let line = "\n" <> expected <> " <http://other.org/p> \"o\" ."
    case string.ends_with(text, line) {
      True -> Nil
      False -> panic as { "expected " <> expected <> " in\n" <> text }
    }
  })
}

pub fn trig_escapes_local_names_exactly_test() {
  let quad =
    statement.Quad(
      subject: term.SubjectNamed(named(ns <> "a/b")),
      predicate: named(ns <> "-p"),
      object: term.ObjectNamed(named(ns <> "o.")),
      graph: term.NamedGraph(named(ns <> "g?1")),
    )
  let text =
    trig.serialize_dataset(dataset.from_list([quad]), None, ex_prefixes())
  string.contains(text, "ex:g\\?1 {\n    ex:a\\/b ex:\\-p ex:o\\. .\n}")
  |> should.be_true
}

pub fn combining_accent_at_namespace_boundary_falls_back_test() {
  // "é" written as "e" followed by U+0301: the namespace ends between the
  // two codepoints, so the local name would start with the accent.
  let iri = "http://ex.org/e\u{0301}x"
  let prefixes = dict.from_list([#("e", "http://ex.org/e")])
  one_iri_turtle(iri, prefixes)
  |> string.ends_with("\n<" <> iri <> "> <http://other.org/p> \"o\" .")
  |> should.be_true

  let text = one_iri_turtle(iri, prefixes)
  let assert Ok(parsed) = turtle.parse_graph(text)
  let assert [triple] = graph.triples(parsed)
  triple.subject |> should.equal(term.SubjectNamed(named(iri)))

  let quad =
    statement.Quad(
      subject: term.SubjectNamed(named(iri)),
      predicate: named("http://other.org/p"),
      object: term.ObjectLiteral(term.SimpleLiteral("o")),
      graph: term.DefaultGraph,
    )
  trig.serialize_dataset(dataset.from_list([quad]), None, prefixes)
  |> string.ends_with("\n<" <> iri <> "> <http://other.org/p> \"o\" .")
  |> should.be_true
}

pub fn shorter_namespace_used_when_longer_one_gives_invalid_local_test() {
  let iri = "http://ex.org/e\u{0301}x"
  let prefixes = dict.from_list([#("e", "http://ex.org/e"), #("ex", ns)])
  one_iri_turtle(iri, prefixes)
  |> string.ends_with("\nex:e\u{0301}x <http://other.org/p> \"o\" .")
  |> should.be_true
}

pub fn same_namespace_prefers_smallest_label_test() {
  let prefixes = dict.from_list([#("zz", ns), #("aa", ns), #("mm", ns)])
  one_iri_turtle(ns <> "x", prefixes)
  |> string.ends_with("\naa:x <http://other.org/p> \"o\" .")
  |> should.be_true
}

/// The tie-break compares codepoints. `string.compare` orders UTF-16 code
/// units on JavaScript, where a character above U+FFFF (a surrogate pair)
/// sorts before U+FF41, so the two targets picked different labels.
pub fn same_namespace_tie_break_is_by_codepoint_on_every_target_test() {
  let prefixes = dict.from_list([#("\u{1F600}", ns), #("\u{FF41}", ns)])
  one_iri_turtle(ns <> "x", prefixes)
  |> string.ends_with("\n\u{FF41}:x <http://other.org/p> \"o\" .")
  |> should.be_true
}

/// `p00` .. `p39`, in order.
fn numbered_labels() -> List(String) {
  list.repeat(Nil, 40)
  |> list.index_map(fn(_, i) {
    "p" <> string.pad_start(int.to_string(i), 2, "0")
  })
}

/// Labels whose dictionary order differs between Erlang and JavaScript
/// (and, past 32 keys, from sorted order on Erlang too).
fn many_prefixes() -> dict.Dict(String, String) {
  let numbered =
    numbered_labels()
    |> list.map(fn(label) { #(label, "http://ex.org/" <> label <> "/") })
  dict.from_list([
    #("", "http://ex.org/e"),
    #("PREFIX", ns),
    #("a", "http://ex.org/a"),
    #("x\u{00B7}", "http://ex.org/b7/"),
    #("\u{1F600}", "http://ex.org/emo/"),
    #("\u{FF41}", "http://ex.org/fw/"),
    #("1bad", "http://ex.org/bad/"),
    ..numbered
  ])
}

fn prefix_lines(text: String) -> List(String) {
  string.split(text, "\n")
  |> list.filter(string.starts_with(_, "@prefix "))
}

fn expected_prefix_lines() -> List(String) {
  let numbered =
    numbered_labels()
    |> list.map(fn(label) {
      "@prefix " <> label <> ": <http://ex.org/" <> label <> "/> ."
    })
  list.flatten([
    [
      "@prefix : <http://ex.org/e> .",
      "@prefix PREFIX: <http://ex.org/> .",
      "@prefix a: <http://ex.org/a> .",
    ],
    numbered,
    [
      "@prefix x\u{00B7}: <http://ex.org/b7/> .",
      "@prefix \u{FF41}: <http://ex.org/fw/> .",
      "@prefix \u{1F600}: <http://ex.org/emo/> .",
    ],
  ])
}

/// The `@prefix` lines followed dictionary iteration order, which differs
/// between Erlang and JavaScript, so the same call gave different bytes on
/// each target. They are now sorted by codepoint (invalid labels dropped).
pub fn turtle_prefix_lines_are_sorted_on_every_target_test() {
  let text =
    turtle.serialize_graph(
      graph.from_list([
        statement.Triple(
          term.SubjectNamed(named(ns <> "s")),
          named(ns <> "p"),
          term.ObjectLiteral(term.SimpleLiteral("o")),
        ),
      ]),
      None,
      many_prefixes(),
    )
  prefix_lines(text) |> should.equal(expected_prefix_lines())
  let assert Ok(_) = turtle.parse(text)
}

pub fn trig_prefix_lines_are_sorted_on_every_target_test() {
  let quad =
    statement.Quad(
      subject: term.SubjectNamed(named(ns <> "s")),
      predicate: named(ns <> "p"),
      object: term.ObjectLiteral(term.SimpleLiteral("o")),
      graph: term.NamedGraph(named(ns <> "g")),
    )
  let text =
    trig.serialize_dataset(dataset.from_list([quad]), None, many_prefixes())
  prefix_lines(text) |> should.equal(expected_prefix_lines())
  let assert Ok(_) = trig.parse(text)
}

pub fn invalid_prefix_labels_are_skipped_test() {
  let prefixes =
    dict.from_list([
      #("1ex", ns),
      #("ex.", ns),
      #("e x", ns),
      #("-ex", ns),
      #("_ex", ns),
    ])
  let text = one_iri_turtle(ns <> "a", prefixes)
  text
  |> should.equal("<http://ex.org/a> <http://other.org/p> \"o\" .")
  let assert Ok(_) = turtle.parse(text)

  let quad =
    statement.Quad(
      subject: term.SubjectNamed(named(ns <> "a")),
      predicate: named("http://other.org/p"),
      object: term.ObjectLiteral(term.SimpleLiteral("o")),
      graph: term.DefaultGraph,
    )
  trig.serialize_dataset(dataset.from_list([quad]), None, prefixes)
  |> should.equal("<http://ex.org/a> <http://other.org/p> \"o\" .")
}

pub fn unusual_valid_prefix_labels_round_trip_test() {
  list.each(["", "é", "ex.1", "a-b", "a_b", "日本"], fn(label) {
    let prefixes = dict.from_list([#(label, ns)])
    let text = one_iri_turtle(ns <> "x/y", prefixes)
    string.contains(text, "\n" <> label <> ":x\\/y ") |> should.be_true
    let assert Ok(document) = turtle.parse(text)
    let assert [triple] = graph.triples(document.graph)
    triple.subject |> should.equal(term.SubjectNamed(named(ns <> "x/y")))
    document.prefixes |> should.equal(prefixes)
  })
}

// Parsing prefixed names ------------------------------------------------------

pub fn turtle_parser_decodes_local_escapes_test() {
  let text =
    "@prefix ex: <http://ex.org/> .\n"
    <> "ex:a\\/b ex:\\-p ex:c%20d .\n"
    <> "ex:x\\~\\.\\!\\$\\&\\'\\(\\)\\*\\+\\,\\;\\=\\?\\#\\@\\%\\_ ex:p ex:: .\n"
    <> "ex:1.2 ex:p ex:a.b.\n"
    <> "ex: ex:p ex:é\u{0301}😀:x .\n"
  let assert Ok(parsed) = turtle.parse_graph(text)
  let expected =
    graph.from_list([
      statement.Triple(
        term.SubjectNamed(named(ns <> "a/b")),
        named(ns <> "-p"),
        term.ObjectNamed(named(ns <> "c%20d")),
      ),
      statement.Triple(
        term.SubjectNamed(named(ns <> "x~.!$&'()*+,;=?#@%_")),
        named(ns <> "p"),
        term.ObjectNamed(named(ns <> ":")),
      ),
      statement.Triple(
        term.SubjectNamed(named(ns <> "1.2")),
        named(ns <> "p"),
        term.ObjectNamed(named(ns <> "a.b")),
      ),
      statement.Triple(
        term.SubjectNamed(named(ns)),
        named(ns <> "p"),
        term.ObjectNamed(named(ns <> "é\u{0301}😀:x")),
      ),
    ])
  same_graph(parsed, expected) |> should.be_true
}

pub fn turtle_parser_rejects_bad_local_escapes_test() {
  let prefix = "@prefix ex: <http://ex.org/> .\n"
  let assert Error(_) = turtle.parse(prefix <> "ex:a\\b ex:p ex:o .")
  let assert Error(_) = turtle.parse(prefix <> "ex:a%4 ex:p ex:o .")
  let assert Error(_) = turtle.parse(prefix <> "ex:a%zz ex:p ex:o .")
}

/// The `@prefix` directive takes PNAME_NS (`ex:`), not a full prefixed name.
/// The parser used to accept `@prefix ex:a <...>` and silently drop the `a`.
pub fn prefix_directive_rejects_a_local_name_test() {
  let body = " <http://ex.org/> .\nex:s ex:p ex:o .\n"
  list.each(["ex:a", "ex:\\/x", "ex:a.b", ":a", "ex::"], fn(label) {
    let assert Error(turtle.TurtleError(_, 8)) =
      turtle.parse("@prefix " <> label <> body)
    let assert Error(trig.TrigError(_, 8)) =
      trig.parse("@prefix " <> label <> body)
  })
  // The valid forms still work: the empty prefix, and no space between the
  // label and the IRI.
  let assert Ok(_) = turtle.parse("@prefix : <http://ex.org/> .\n:s :p :o .")
  let assert Ok(doc) =
    turtle.parse("@prefix ex:<http://ex.org/>.\nex:s ex:p ex:o.")
  dict.get(doc.prefixes, "ex") |> should.equal(Ok("http://ex.org/"))
}

// Byte order marks ------------------------------------------------------------

const nt_statement = "<http://ex.org/s> <http://ex.org/p> \"o\" .\n"

const nq_statement =
  "<http://ex.org/s> <http://ex.org/p> \"o\" <http://ex.org/g> .\n"

const ttl_document = "@prefix ex: <http://ex.org/> .\nex:s ex:p \"o\" .\n"

pub fn ntriples_parse_strips_one_leading_bom_test() {
  let assert Ok(expected) = ntriples.parse(nt_statement)
  ntriples.parse(bom <> nt_statement) |> should.equal(Ok(expected))
  ntriples.parse_graph(bom <> nt_statement)
  |> should.equal(Ok(expected.graph))
  let assert Error(ntriples.NTriplesError(_, 1)) =
    ntriples.parse(bom <> bom <> nt_statement)
  let assert Error(ntriples.NTriplesError(_, 2)) =
    ntriples.parse(nt_statement <> bom <> nt_statement)
}

pub fn nquads_parse_strips_one_leading_bom_test() {
  let assert Ok(expected) = nquads.parse(nq_statement)
  nquads.parse(bom <> nq_statement) |> should.equal(Ok(expected))
  nquads.parse_dataset(bom <> nq_statement)
  |> should.equal(Ok(expected.dataset))
  let assert Error(nquads.NQuadsError(_, 1)) =
    nquads.parse(bom <> bom <> nq_statement)
  let assert Error(nquads.NQuadsError(_, 2)) =
    nquads.parse(nq_statement <> bom <> nq_statement)
}

pub fn turtle_parse_strips_one_leading_bom_test() {
  let assert Ok(expected) = turtle.parse(ttl_document)
  turtle.parse(bom <> ttl_document) |> should.equal(Ok(expected))
  turtle.parse_graph(bom <> ttl_document)
  |> should.equal(Ok(expected.graph))
  let assert Error(_) = turtle.parse(bom <> bom <> ttl_document)
  let assert Error(_) = turtle.parse(ttl_document <> bom)
}

pub fn trig_parse_strips_one_leading_bom_test() {
  let assert Ok(expected) = trig.parse(ttl_document)
  trig.parse(bom <> ttl_document) |> should.equal(Ok(expected))
  trig.parse_dataset(bom <> ttl_document)
  |> should.equal(Ok(expected.dataset))
  let assert Error(_) = trig.parse(bom <> bom <> ttl_document)
  let assert Error(_) = trig.parse(ttl_document <> bom)
}

/// Writes `content` to a fresh file under `build/`, runs `work` on its path
/// and deletes the file again.
fn with_file(name: String, content: String, work: fn(String) -> a) -> a {
  let path =
    "build/tmp_names_bom_"
    <> name
    <> "_"
    <> int.to_string(int.random(1_000_000_000))
  let assert Ok(Nil) = simplifile.write(path, content)
  let result = work(path)
  let _ = simplifile.delete(path)
  result
}

pub fn parse_file_and_parse_agree_on_byte_order_marks_test() {
  list.each(["", bom, bom <> bom], fn(prefix) {
    let nt = prefix <> nt_statement
    with_file("nt", nt, fn(path) {
      ntriples.parse_file(path) |> should.equal(ntriples.parse(nt))
      ntriples.streaming_parse_file(path)
      |> should.equal(ntriples.parse(nt))
    })
    let nq = prefix <> nq_statement
    with_file("nq", nq, fn(path) {
      nquads.parse_file(path) |> should.equal(nquads.parse(nq))
      nquads.streaming_parse_file(path) |> should.equal(nquads.parse(nq))
    })
    let ttl = prefix <> ttl_document
    with_file("ttl", ttl, fn(path) {
      turtle.parse_file(path) |> should.equal(turtle.parse(ttl))
      trig.parse_file(path) |> should.equal(trig.parse(ttl))
    })
  })
}

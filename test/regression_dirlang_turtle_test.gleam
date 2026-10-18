//// Regression tests for RDF 1.2 directional language-tagged strings
//// (`"value"@tag--ltr` / `--rtl`) in Turtle and TriG, and for the gaps found
//// while wiring them in:
////
//// - The Turtle and TriG parsers rejected `"a"@en--ltr` ("Invalid language
////   tag"), read only `"..."` strings, and could not read triple terms.
//// - The writers wrote triple terms as `<<s p o>>`, which Turtle 1.2 reads
////   as a reified triple (a different graph), and escaped strings and IRIs
////   per grapheme cluster, so a `"` followed by a combining accent or a
////   CR LF pair was written raw.
//// - `trig.parse` returned an empty dataset for any text containing
////   `GRAPH ` or ` {` (even inside a string), so named graphs never read
////   back.
////
//// Every test runs on both Erlang and JavaScript.

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

const prefix_ex = "@prefix ex: <http://ex.org/> .\n"

// Helpers ---------------------------------------------------------------------

fn iri(local: String) -> term.NamedNode {
  let assert Ok(node) = term.named_node(ns <> local)
  node
}

fn dir(value: String, tag: String, direction: String) -> term.Literal {
  let assert Ok(literal) =
    term.directional_language_literal_from_strings(value, tag, direction)
  literal
}

fn lang(value: String, tag: String) -> term.Literal {
  let assert Ok(tag) = term.language_tag(tag)
  term.language_literal(value, tag)
}

fn triple(s: String, p: String, object: term.Object) -> statement.Triple {
  statement.triple(term.SubjectNamed(iri(s)), iri(p), object)
}

fn lit(literal: term.Literal) -> term.Object {
  term.ObjectLiteral(literal)
}

fn ex_prefixes() -> dict.Dict(String, String) {
  dict.from_list([#("ex", ns)])
}

fn ttl_graph(text: String) -> graph.Graph {
  case turtle.parse_graph(text) {
    Ok(parsed) -> parsed
    Error(turtle.TurtleError(message, position)) ->
      panic as {
        "Turtle parse failed at "
        <> int.to_string(position)
        <> ": "
        <> message
        <> "\n"
        <> text
      }
  }
}

fn trig_dataset(text: String) -> dataset.Dataset {
  case trig.parse_dataset(text) {
    Ok(parsed) -> parsed
    Error(trig.TrigError(message, position)) ->
      panic as {
        "TriG parse failed at "
        <> int.to_string(position)
        <> ": "
        <> message
        <> "\n"
        <> text
      }
  }
}

fn ttl_object(object_text: String) -> term.Object {
  let assert [parsed] =
    graph.triples(ttl_graph(
      "<http://ex.org/s> <http://ex.org/p> " <> object_text <> " .",
    ))
  parsed.object
}

fn ttl_error(text: String) -> String {
  let assert Error(turtle.TurtleError(message, _)) = turtle.parse(text)
  message
}

fn same_graph(actual: graph.Graph, expected: graph.Graph) -> Bool {
  graph.size(actual) == graph.size(expected)
  && list.all(graph.triples(expected), graph.contains(actual, _))
}

fn same_dataset(actual: dataset.Dataset, expected: dataset.Dataset) -> Bool {
  dataset.quad_count(actual) == dataset.quad_count(expected)
  && list.all(dataset.quads(expected), dataset.contains_quad(actual, _))
}

/// Every literal kind for the same value and tag, plus non-ASCII and
/// awkward values, so a writer or parser that drops or mixes up the
/// direction is caught.
fn mixed_triples() -> List(statement.Triple) {
  [
    triple("s", "p", lit(dir("hello", "en", "ltr"))),
    triple("s", "p", lit(dir("hello", "en", "rtl"))),
    triple("s", "p", lit(lang("hello", "en"))),
    triple("s", "p", lit(term.SimpleLiteral("hello"))),
    triple("s", "q", lit(dir("שלום", "he", "rtl"))),
    triple("s", "q", lit(dir("مرحبا", "ar-EG", "rtl"))),
    triple("s", "q", lit(dir("x", "de-CH-1996", "ltr"))),
    triple("s", "r", lit(dir("say \"hi\"\nnext\ttab \\ end", "en-US", "ltr"))),
    triple("s", "r", lit(dir("\"\u{0301} and \r\n", "fr", "rtl"))),
    triple("s", "r", lit(dir("", "en", "ltr"))),
    triple(
      "s",
      "t",
      term.ObjectTriple(term.triple_term(
        term.SubjectNamed(iri("a")),
        iri("b"),
        lit(dir("inner", "ar", "rtl")),
      )),
    ),
  ]
}

// Parsing ---------------------------------------------------------------------

pub fn turtle_parses_directional_literals_test() {
  ttl_object("\"Hello\"@en--ltr")
  |> should.equal(lit(dir("Hello", "en", "ltr")))
  ttl_object("\"שלום\"@he--rtl")
  |> should.equal(lit(dir("שלום", "he", "rtl")))
}

pub fn turtle_directional_literal_differs_from_plain_language_tag_test() {
  should.not_equal(ttl_object("\"a\"@en--ltr"), ttl_object("\"a\"@en"))
  should.not_equal(ttl_object("\"a\"@en--ltr"), ttl_object("\"a\"@en--rtl"))
  ttl_object("\"a\"@en") |> should.equal(lit(lang("a", "en")))
}

pub fn turtle_parses_all_four_string_forms_with_direction_test() {
  let expected = lit(dir("a 'b' \"c\"", "ar", "rtl"))
  ttl_object("\"a 'b' \\\"c\\\"\"@ar--rtl") |> should.equal(expected)
  ttl_object("'a \\'b\\' \"c\"'@ar--rtl") |> should.equal(expected)
  ttl_object("\"\"\"a 'b' \"c\\\"\"\"\"@ar--rtl") |> should.equal(expected)
  ttl_object("'''a 'b' \"c\"'''@ar--rtl") |> should.equal(expected)
}

pub fn turtle_long_strings_keep_raw_line_breaks_test() {
  ttl_object("\"\"\"line 1\nline \"2\"\r\n\"\"\"@en--ltr")
  |> should.equal(lit(dir("line 1\nline \"2\"\r\n", "en", "ltr")))
  ttl_object("'''it''s\n'''@en--rtl")
  |> should.equal(lit(dir("it''s\n", "en", "rtl")))
  ttl_object("\"\"\"\"\"\"@en--ltr") |> should.equal(lit(dir("", "en", "ltr")))
  ttl_object("''@en--ltr") |> should.equal(lit(dir("", "en", "ltr")))
}

pub fn turtle_short_strings_reject_raw_line_breaks_test() {
  ttl_error("<http://ex.org/s> <http://ex.org/p> 'a\nb'@en--ltr .")
  |> should.equal("Line break not allowed in string")
  ttl_error("<http://ex.org/s> <http://ex.org/p> \"a\rb\"@en--ltr .")
  |> should.equal("Line break not allowed in string")
  let assert Error(_) =
    turtle.parse("<http://ex.org/s> <http://ex.org/p> \"\"\"open .")
}

pub fn turtle_parses_echar_escapes_test() {
  ttl_object("'\\t\\b\\n\\r\\f\\\"\\'\\\\'@en--ltr")
  |> should.equal(lit(dir("\t\u{0008}\n\r\u{000C}\"'\\", "en", "ltr")))
}

pub fn turtle_tag_is_case_insensitive_and_may_have_digits_test() {
  ttl_object("\"x\"@EN-us--rtl") |> should.equal(lit(dir("x", "en-US", "rtl")))
  ttl_object("\"x\"@de-CH-1996--ltr")
  |> should.equal(lit(dir("x", "de-CH-1996", "ltr")))
  // Before RDF 1.2 support the lexer stopped at digits in a tag.
  ttl_object("\"x\"@de-CH-1996") |> should.equal(lit(lang("x", "de-CH-1996")))
}

pub fn turtle_directional_literals_in_object_and_predicate_lists_test() {
  let parsed =
    ttl_graph(
      prefix_ex
      <> "ex:s ex:p \"a\"@en--ltr, 'b'@he--rtl, \"\"\"c\"\"\"@en ;\n"
      <> "     ex:q '''d'''@ar--rtl ;\n"
      <> "     ex:r \"e\"@en--ltr .",
    )
  let expected = [
    triple("s", "p", lit(dir("a", "en", "ltr"))),
    triple("s", "p", lit(dir("b", "he", "rtl"))),
    triple("s", "p", lit(lang("c", "en"))),
    triple("s", "q", lit(dir("d", "ar", "rtl"))),
    triple("s", "r", lit(dir("e", "en", "ltr"))),
  ]
  same_graph(parsed, graph.from_list(expected)) |> should.be_true
}

pub fn turtle_directional_literal_before_statement_dot_test() {
  // No space between the direction and the '.' / ';' / ','.
  let parsed =
    ttl_graph(
      prefix_ex <> "ex:s ex:p \"a\"@en--ltr,\"b\"@en--rtl;ex:q \"c\"@en--ltr.",
    )
  graph.size(parsed) |> should.equal(3)
  graph.contains(parsed, triple("s", "q", lit(dir("c", "en", "ltr"))))
  |> should.be_true
}

pub fn turtle_directional_literals_inside_triple_terms_test() {
  let inner =
    term.triple_term(
      term.SubjectNamed(iri("a")),
      iri("b"),
      lit(dir("x", "ar", "rtl")),
    )
  ttl_object("<<( <http://ex.org/a> <http://ex.org/b> \"x\"@ar--rtl )>>")
  |> should.equal(term.ObjectTriple(inner))

  // Nested, in subject position, with prefixed names and 'a'.
  let parsed =
    ttl_graph(
      prefix_ex
      <> "<<( <<( ex:a ex:b 'x'@ar--rtl )>> a ex:C )>> ex:says \"\"\"y\"\"\"@en--ltr .",
    )
  let rdf_type =
    term.unsafe_named_node("http://www.w3.org/1999/02/22-rdf-syntax-ns#type")
  let outer =
    term.triple_term(
      term.SubjectTriple(inner),
      rdf_type,
      term.ObjectNamed(iri("C")),
    )
  let expected =
    statement.triple(
      term.SubjectTriple(outer),
      iri("says"),
      lit(dir("y", "en", "ltr")),
    )
  graph.triples(parsed) |> should.equal([expected])
}

pub fn turtle_rejects_reified_triple_syntax_with_clear_error_test() {
  let message =
    ttl_error(
      "<< <http://ex.org/a> <http://ex.org/b> \"x\"@en--ltr >> <http://ex.org/p> <http://ex.org/o> .",
    )
  string.contains(message, "<<( s p o )>>") |> should.be_true
  let assert Error(_) =
    turtle.parse(
      "<http://ex.org/s> <http://ex.org/p> <<( <http://ex.org/a> <http://ex.org/b> \"x\" .",
    )
}

// Rejection, matching N-Triples -------------------------------------------------

pub fn turtle_rejects_invalid_directions_like_ntriples_test() {
  let cases = [
    #("en--up", "Invalid base direction 'up' in @en--up (expected ltr or rtl)"),
    #("en--", "Invalid base direction '' in @en-- (expected ltr or rtl)"),
    #(
      "en---ltr",
      "Invalid base direction '-ltr' in @en---ltr (expected ltr or rtl)",
    ),
    #(
      "en--ltr--rtl",
      "Invalid base direction 'ltr--rtl' in @en--ltr--rtl (expected ltr or rtl)",
    ),
    #("--ltr", "Missing language tag before base direction in @--ltr"),
    #("1en--ltr", "Invalid language tag: 1en"),
    #(
      "en--l2r",
      "Invalid base direction 'l2r' in @en--l2r (expected ltr or rtl)",
    ),
    // W3C nt-ttl12-langdir-bad-2 ("upper case LTR"): RDF 1.2 requires the
    // lowercase strings `ltr` / `rtl`.
    #(
      "en--LTR",
      "Invalid base direction 'LTR' in @en--LTR (expected ltr or rtl)",
    ),
    #(
      "en-US--Rtl",
      "Invalid base direction 'Rtl' in @en-US--Rtl (expected ltr or rtl)",
    ),
  ]
  list.each(cases, fn(pair) {
    let #(suffix, expected) = pair
    let statement =
      "<http://ex.org/s> <http://ex.org/p> \"v\"@" <> suffix <> " ."
    ttl_error(statement) |> should.equal(expected)
    let assert Error(trig.TrigError(trig_message, _)) = trig.parse(statement)
    trig_message |> should.equal(expected)
    let assert Error(ntriples.NTriplesError(nt_message, _)) =
      ntriples.parse(statement)
    string.contains(nt_message, expected) |> should.be_true
  })
}

/// W3C ntriples-langdir-bad-3 / -bad-5 in Turtle and TriG: `rdf:langString`
/// and `rdf:dirLangString` need a language tag, so they cannot be written
/// with `^^`. Both were read as plain typed literals and round-tripped.
pub fn turtle_and_trig_reject_lang_string_datatypes_test() {
  let rdf = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
  [
    #("<" <> rdf <> "dirLangString>", "rdf:dirLangString"),
    #("<" <> rdf <> "langString>", "rdf:langString"),
    #("rdf:dirLangString", "rdf:dirLangString"),
    #("rdf:langString", "rdf:langString"),
  ]
  |> list.each(fn(pair) {
    let #(datatype, expected) = pair
    let body = "ex:s ex:p \"x\"^^" <> datatype
    let prologue = prefix_ex <> "@prefix rdf: <" <> rdf <> "> .\n"
    let ttl = prologue <> body <> " ."
    string.contains(ttl_error(ttl), expected) |> should.be_true
    let assert Error(trig.TrigError(message, _)) = trig.parse(ttl)
    string.contains(message, expected) |> should.be_true
    let assert Error(trig.TrigError(message, _)) =
      trig.parse(prologue <> "ex:g { " <> body <> " }")
    string.contains(message, expected) |> should.be_true
    let assert Error(trig.TrigError(message, _)) =
      trig.parse(
        prologue
        <> "ex:g { ex:s ex:p <<( ex:a ex:b \"x\"^^"
        <> datatype
        <> " )>> }",
      )
    string.contains(message, expected) |> should.be_true
  })
  // Other rdf: datatypes still work.
  ttl_object("\"<b/>\"^^<" <> rdf <> "XMLLiteral>")
  |> should.equal(
    lit(term.typed_literal("<b/>", term.NamedNode(rdf <> "XMLLiteral"))),
  )
}

/// The error points at the datatype, like other datatype errors.
pub fn turtle_lang_string_datatype_error_points_at_the_datatype_test() {
  let text =
    "<http://ex.org/s> <http://ex.org/p> 'v'^^<http://www.w3.org/1999/02/22-rdf-syntax-ns#dirLangString> ."
  let assert Error(turtle.TurtleError(_, position)) = turtle.parse(text)
  position |> should.equal(41)
}

/// TriG uses the same LANG_DIR rule: uppercase directions are rejected
/// inside graph blocks too.
pub fn trig_rejects_uppercase_direction_in_graph_block_test() {
  let assert Error(trig.TrigError(message, _)) =
    trig.parse("@prefix : <http://e/> .\n:G { :a :b \"Hello\"@en--LTR }")
  message
  |> should.equal(
    "Invalid base direction 'LTR' in @en--LTR (expected ltr or rtl)",
  )
}

pub fn turtle_invalid_direction_error_points_at_the_tag_test() {
  let text = "<http://ex.org/s> <http://ex.org/p> 'v'@en--up ."
  let assert Error(turtle.TurtleError(_, position)) = turtle.parse(text)
  position |> should.equal(39)
}

pub fn turtle_rejects_invalid_direction_in_every_position_test() {
  let bad = "\"v\"@en--up"
  [
    "<http://ex.org/s> <http://ex.org/p> <<( <http://ex.org/a> <http://ex.org/b> "
      <> bad
      <> " )>> .",
    "<http://ex.org/s> <http://ex.org/p> \"ok\"@en--ltr, " <> bad <> " .",
    "<http://ex.org/s> <http://ex.org/p> '''v'''@en--up .",
  ]
  |> list.each(fn(text) {
    string.starts_with(ttl_error(text), "Invalid base direction 'up'")
    |> should.be_true
  })
}

// Writing ---------------------------------------------------------------------

pub fn turtle_writes_lang_dir_suffix_test() {
  let text =
    turtle.serialize_graph(
      graph.from_list([
        triple("s", "p", lit(dir("x", "en", "ltr"))),
        triple("s", "q", lit(dir("y", "en-US", "rtl"))),
      ]),
      None,
      ex_prefixes(),
    )
  string.contains(text, "\nex:s ex:p \"x\"@en--ltr .") |> should.be_true
  string.contains(text, "\nex:s ex:q \"y\"@en-US--rtl .") |> should.be_true
}

pub fn trig_writes_lang_dir_suffix_in_named_graph_test() {
  let data =
    dataset.from_list([
      statement.quad(
        triple("s", "p", lit(dir("x", "ar", "rtl"))),
        term.NamedGraph(iri("g")),
      ),
    ])
  let text = trig.serialize_dataset(data, None, ex_prefixes())
  string.contains(text, "ex:g {\n    ex:s ex:p \"x\"@ar--rtl .\n}")
  |> should.be_true
}

pub fn writers_use_rdf12_triple_term_syntax_test() {
  let data = [
    triple(
      "s",
      "p",
      term.ObjectTriple(term.triple_term(
        term.SubjectNamed(iri("a")),
        iri("b"),
        lit(dir("x", "en", "ltr")),
      )),
    ),
  ]
  let expected = "ex:s ex:p <<( ex:a ex:b \"x\"@en--ltr )>> ."
  turtle.serialize_graph(graph.from_list(data), None, ex_prefixes())
  |> string.contains(expected)
  |> should.be_true
  trig.serialize_dataset(
    dataset.from_list(list.map(data, statement.quad(_, term.DefaultGraph))),
    None,
    ex_prefixes(),
  )
  |> string.contains(expected)
  |> should.be_true
}

pub fn writers_escape_per_codepoint_test() {
  // A '"' followed by a combining accent is a single grapheme cluster, as
  // is CR LF; escaping per cluster left both raw.
  let data = [triple("s", "p", lit(dir("\"\u{0301}\r\n", "en", "ltr")))]
  let expected = "\"\\\"\u{0301}\\r\\n\"@en--ltr ."
  turtle.serialize_graph(graph.from_list(data), None, dict.new())
  |> string.contains(expected)
  |> should.be_true
  trig.serialize_dataset(
    dataset.from_list(list.map(data, statement.quad(_, term.DefaultGraph))),
    None,
    dict.new(),
  )
  |> string.contains(expected)
  |> should.be_true
}

// Round trips -----------------------------------------------------------------

pub fn turtle_round_trip_test() {
  let original = graph.from_list(mixed_triples())
  let text = turtle.serialize_graph(original, None, ex_prefixes())
  let parsed = ttl_graph(text)
  same_graph(parsed, original) |> should.be_true
  graph.isomorphic(parsed, original) |> should.be_true
  // Writing the parsed graph again reads back the same graph.
  turtle.serialize_graph(parsed, None, ex_prefixes())
  |> ttl_graph
  |> same_graph(original)
  |> should.be_true
}

pub fn trig_round_trip_with_named_graphs_test() {
  let triples = mixed_triples()
  let original =
    dataset.from_list(
      list.flatten([
        list.map(triples, statement.quad(_, term.DefaultGraph)),
        list.map(triples, statement.quad(_, term.NamedGraph(iri("g1")))),
        list.map(triples, statement.quad(_, term.NamedGraph(iri("g/2")))),
      ]),
    )
  let text = trig.serialize_dataset(original, None, ex_prefixes())
  let parsed = trig_dataset(text)
  same_dataset(parsed, original) |> should.be_true
  dataset.isomorphic(parsed, original) |> should.be_true
}

pub fn trig_round_trip_with_blank_graph_name_test() {
  let quad =
    statement.quad(
      triple("s", "p", lit(dir("x", "en", "rtl"))),
      term.BlankGraph(term.BlankNode("g0")),
    )
  let original = dataset.from_list([quad])
  let parsed =
    trig.serialize_dataset(original, None, dict.new()) |> trig_dataset
  dataset.isomorphic(parsed, original) |> should.be_true
  dataset.graph_names(parsed) |> list.length |> should.equal(1)
}

pub fn turtle_to_ntriples_to_turtle_test() {
  let source =
    prefix_ex
    <> "ex:s ex:p \"a\"@en--ltr, 'b'@he--rtl, \"\"\"c\nd\"\"\"@ar-EG--rtl, \"e\"@en ;\n"
    <> "  ex:q <<( ex:a ex:b '''f'''@fa--rtl )>> .\n"
    <> "<<( ex:x ex:y \"g\"@en--ltr )>> ex:z \"h\" ."
  let from_turtle = ttl_graph(source)
  graph.size(from_turtle) |> should.equal(6)

  let nt_text = ntriples.serialize_graph(from_turtle)
  string.contains(nt_text, "\"b\"@he--rtl") |> should.be_true
  string.contains(
    nt_text,
    "<<( <http://ex.org/a> <http://ex.org/b> \"f\"@fa--rtl )>>",
  )
  |> should.be_true
  let assert Ok(from_ntriples) = ntriples.parse_graph(nt_text)
  same_graph(from_ntriples, from_turtle) |> should.be_true

  let back = turtle.serialize_graph(from_ntriples, None, ex_prefixes())
  let from_turtle_again = ttl_graph(back)
  same_graph(from_turtle_again, from_turtle) |> should.be_true
  graph.isomorphic(from_turtle_again, from_ntriples) |> should.be_true
}

pub fn trig_to_nquads_to_trig_test() {
  let source =
    prefix_ex
    <> "ex:s ex:p 'top'@en--ltr .\n"
    <> "GRAPH ex:g1 { ex:s ex:p \"a\"@en--ltr . ex:s ex:p \"a\"@en--rtl }\n"
    <> "ex:g2 { ex:s ex:q <<( ex:a ex:b \"\"\"x\"\"\"@ar--rtl )>> . }\n"
    <> "{ ex:s ex:r \"b\"@he--rtl }"
  let from_trig = trig_dataset(source)
  dataset.quad_count(from_trig) |> should.equal(5)
  dataset.graph_names(from_trig) |> list.length |> should.equal(2)

  let assert Ok(from_nquads) =
    nquads.parse_dataset(nquads.serialize_dataset(from_trig))
  same_dataset(from_nquads, from_trig) |> should.be_true

  let from_trig_again =
    trig.serialize_dataset(from_nquads, None, ex_prefixes()) |> trig_dataset
  same_dataset(from_trig_again, from_trig) |> should.be_true
  dataset.isomorphic(from_trig_again, from_nquads) |> should.be_true
}

pub fn turtle_and_ntriples_parse_to_isomorphic_graphs_test() {
  let ttl =
    prefix_ex
    <> "_:b ex:p \"a\"@en--ltr .\n_:b ex:q <<( ex:c ex:r 'z'@ar--rtl )>> ."
  // graph.isomorphic does not relabel blank nodes inside triple terms (see
  // docs/ISOMORPHISM.md), so the triple term uses IRIs only.
  let nt =
    "_:x <http://ex.org/p> \"a\"@en--ltr .\n"
    <> "_:x <http://ex.org/q> <<( <http://ex.org/c> <http://ex.org/r> \"z\"@ar--rtl )>> .\n"
  let assert Ok(from_nt) = ntriples.parse_graph(nt)
  graph.isomorphic(ttl_graph(ttl), from_nt) |> should.be_true

  // Changing only the direction breaks the isomorphism, both ways round.
  let flipped = string.replace(nt, "@ar--rtl", "@ar--ltr")
  let assert Ok(from_flipped) = ntriples.parse_graph(flipped)
  graph.isomorphic(ttl_graph(ttl), from_flipped) |> should.be_false
  let undirected = string.replace(nt, "@en--ltr", "@en")
  let assert Ok(from_undirected) = ntriples.parse_graph(undirected)
  graph.isomorphic(ttl_graph(ttl), from_undirected) |> should.be_false
}

pub fn turtle_file_round_trip_test() {
  let original = graph.from_list(mixed_triples())
  let path = "build/regression_dirlang_turtle.ttl"
  let assert Ok(Nil) =
    turtle.serialize_graph_to_file(original, None, ex_prefixes(), path)
  let assert Ok(parsed) = turtle.parse_graph_file(path)
  let _ = simplifile.delete(path)
  same_graph(parsed, original) |> should.be_true
}

pub fn trig_file_round_trip_test() {
  let original =
    dataset.from_list(
      list.map(mixed_triples(), statement.quad(_, term.NamedGraph(iri("g")))),
    )
  let path = "build/regression_dirlang_turtle.trig"
  let assert Ok(Nil) =
    trig.serialize_dataset_to_file(original, None, ex_prefixes(), path)
  let assert Ok(parsed) = trig.parse_dataset_file(path)
  let _ = simplifile.delete(path)
  same_dataset(parsed, original) |> should.be_true
}

// TriG graph blocks -------------------------------------------------------------

pub fn trig_reads_every_graph_block_form_test() {
  let parsed =
    trig_dataset(
      prefix_ex
      <> "{ ex:s ex:p \"d\"@en--ltr }\n"
      <> "ex:g1 { ex:s ex:p \"1\"@en--ltr . ex:s ex:q \"2\"@en--rtl . }\n"
      <> "graph ex:g2 { }\n"
      <> "GRAPH <http://ex.org/g3> { ex:s ex:p '3'@he--rtl }\n"
      <> "_:g4 { ex:s ex:p '''4'''@ar--rtl }\n"
      <> "@prefix other: <http://other.org/> .\n"
      <> "other:g5 { other:s ex:p \"5\"@en--ltr }",
    )
  dataset.quad_count(parsed) |> should.equal(6)
  dataset.contains_quad(
    parsed,
    statement.quad(
      triple("s", "p", lit(dir("d", "en", "ltr"))),
      term.DefaultGraph,
    ),
  )
  |> should.be_true
  dataset.contains_quad(
    parsed,
    statement.quad(
      triple("s", "q", lit(dir("2", "en", "rtl"))),
      term.NamedGraph(iri("g1")),
    ),
  )
  |> should.be_true
  dataset.contains_quad(
    parsed,
    statement.quad(
      triple("s", "p", lit(dir("3", "he", "rtl"))),
      term.NamedGraph(iri("g3")),
    ),
  )
  |> should.be_true
  let g5 = term.NamedGraph(term.unsafe_named_node("http://other.org/g5"))
  graph.size(dataset.graph(parsed, g5)) |> should.equal(1)
}

pub fn trig_text_with_brace_inside_a_string_is_not_dropped_test() {
  // The old heuristic treated any " {" as TriG syntax and returned nothing.
  let text = "<http://ex.org/s> <http://ex.org/p> \"a {b} GRAPH \"@en--ltr ."
  let parsed = trig_dataset(text)
  dataset.quad_count(parsed) |> should.equal(1)
  dataset.contains_triple(
    parsed,
    triple("s", "p", lit(dir("a {b} GRAPH ", "en", "ltr"))),
    term.DefaultGraph,
  )
  |> should.be_true
}

pub fn trig_rejects_malformed_graph_blocks_test() {
  [
    "<http://ex.org/g> { <http://ex.org/s> <http://ex.org/p> \"o\"@en--ltr",
    "<http://ex.org/g> { <http://ex.org/s> <http://ex.org/p> \"o\" <http://ex.org/x> }",
    "GRAPH { <http://ex.org/s> <http://ex.org/p> \"o\" }",
    "GRAPH <http://ex.org/g> <http://ex.org/s> <http://ex.org/p> \"o\" .",
    "<http://ex.org/g> { <http://ex.org/h> { } }",
    "\"lit\" { }",
  ]
  |> list.each(fn(text) {
    case trig.parse(text) {
      Error(_) -> Nil
      Ok(_) -> panic as { "expected a TriG error for: " <> text }
    }
  })
}

pub fn turtle_rejects_graph_blocks_test() {
  let assert Error(_) =
    turtle.parse(
      "<http://ex.org/g> { <http://ex.org/s> <http://ex.org/p> \"o\"@en--ltr }",
    )
  let assert Error(_) =
    turtle.parse("{ <http://ex.org/s> <http://ex.org/p> \"o\" }")
}

pub fn turtle_directive_between_statements_test() {
  let parsed =
    ttl_graph(
      prefix_ex
      <> "ex:s ex:p \"a\"@en--ltr .\n"
      <> "@prefix ex: <http://ex.org/other/> .\n"
      <> "ex:s ex:p \"b\"@en--rtl .",
    )
  graph.contains(
    parsed,
    statement.triple(
      term.SubjectNamed(term.unsafe_named_node("http://ex.org/other/s")),
      term.unsafe_named_node("http://ex.org/other/p"),
      lit(dir("b", "en", "rtl")),
    ),
  )
  |> should.be_true
  graph.contains(parsed, triple("s", "p", lit(dir("a", "en", "ltr"))))
  |> should.be_true
}

// Integration with the prefixed-name and BOM fixes -------------------------------

pub fn bom_and_escaped_local_names_with_directional_literals_test() {
  let bom = "\u{FEFF}"
  let original = [
    statement.triple(
      term.SubjectNamed(iri("a/b")),
      iri("-p"),
      lit(dir("x", "en", "ltr")),
    ),
    statement.triple(
      term.SubjectNamed(iri("a.")),
      iri("p"),
      term.ObjectLiteral(term.TypedLiteral("y", iri("dt/1"))),
    ),
  ]
  let text =
    turtle.serialize_graph(graph.from_list(original), None, ex_prefixes())
  string.contains(text, "ex:a\\/b ex:\\-p \"x\"@en--ltr .") |> should.be_true
  same_graph(ttl_graph(bom <> text), graph.from_list(original))
  |> should.be_true
  dataset.default_graph(trig_dataset(bom <> text))
  |> same_graph(graph.from_list(original))
  |> should.be_true
  let assert Error(_) = turtle.parse(bom <> bom <> text)
}

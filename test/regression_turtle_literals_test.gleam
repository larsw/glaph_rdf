//// Regression tests for Turtle and TriG round-trips of numeric and boolean
//// literals and of blank node labels containing '.', plus the matching
//// lexer rules (case-sensitive `true` / `false`, the Turtle number grammar).
////
//// The writers used to print every xsd:integer, xsd:decimal, xsd:double and
//// xsd:boolean literal bare without checking its lexical form, so
//// ill-typed or unusual literals came out unparseable or changed, and the
//// lexer could not read the '.' inside a label such as `_:b.1`. Every test
//// runs on both Erlang and JavaScript.

import glaph_rdf/dataset
import glaph_rdf/graph
import glaph_rdf/serializers/nquads
import glaph_rdf/serializers/ntriples
import glaph_rdf/serializers/trig
import glaph_rdf/serializers/turtle
import glaph_rdf/term
import gleam/dict
import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit/should

const xsd = "http://www.w3.org/2001/XMLSchema#"

fn statement(object: String) -> String {
  "<http://e/s> <http://e/p> " <> object <> " .\n"
}

fn typed(value: String, datatype: String) -> String {
  statement("\"" <> value <> "\"^^<" <> xsd <> datatype <> ">")
}

/// Write the N-Triples input as Turtle (with and without an xsd prefix),
/// read it back, and require the same graph.
fn assert_turtle_round_trip(text: String) {
  let assert Ok(original) = ntriples.parse_graph(text)
  list.each(
    [dict.new(), dict.from_list([#("xsd", xsd), #("e", "http://e/")])],
    fn(prefixes) {
      let written = turtle.serialize_graph(original, None, prefixes)
      case turtle.parse_graph(written) {
        Ok(read) -> graph.isomorphic(original, read) |> should.be_true
        Error(error) ->
          panic as {
            "Turtle round trip failed for " <> written <> string.inspect(error)
          }
      }
    },
  )
}

/// The same through TriG, with the statement in a named and in a blank graph.
fn assert_trig_round_trip(text: String) {
  list.each(["<http://e/g>", "_:g"], fn(graph_name) {
    let quads =
      text
      |> string.split(" .\n")
      |> list.filter(fn(line) { line != "" })
      |> list.map(fn(line) { line <> " " <> graph_name <> " .\n" })
      |> string.concat
    let assert Ok(original) = nquads.parse_dataset(quads)
    let written = trig.serialize_dataset(original, None, dict.new())
    case trig.parse_dataset(written) {
      Ok(read) -> dataset.isomorphic(original, read) |> should.be_true
      Error(error) ->
        panic as {
          "TriG round trip failed for " <> written <> string.inspect(error)
        }
    }
  })
}

fn assert_round_trips(text: String) {
  assert_turtle_round_trip(text)
  assert_trig_round_trip(text)
}

fn written_object(text: String) -> String {
  let assert Ok(original) = ntriples.parse_graph(text)
  let written = turtle.serialize_graph(original, None, dict.new())
  let assert Ok(line) =
    written
    |> string.split("\n")
    |> list.find(fn(line) { string.starts_with(line, "<http://e/s>") })
  line
  |> string.replace("<http://e/s> <http://e/p> ", "")
  |> string.replace(" .", "")
}

fn parsed_object(turtle_text: String) -> Result(term.Object, Nil) {
  case turtle.parse_graph(turtle_text) {
    Ok(parsed) ->
      case graph.triples(parsed) {
        [triple] -> Ok(triple.object)
        _ -> Error(Nil)
      }
    Error(_) -> Error(Nil)
  }
}

fn literal(value: String, datatype: String) -> Result(term.Object, Nil) {
  Ok(
    term.ObjectLiteral(term.TypedLiteral(
      value,
      term.unsafe_named_node(xsd <> datatype),
    )),
  )
}

// Writer ----------------------------------------------------------------------

pub fn ill_typed_numeric_literals_round_trip_test() {
  assert_round_trips(typed("abc", "integer"))
  assert_round_trips(typed("", "integer"))
  assert_round_trips(typed("", "decimal"))
  assert_round_trips(typed("yes", "boolean"))
  assert_round_trips(typed(" 1", "integer"))
  assert_round_trips(typed("1.", "decimal"))
  assert_round_trips(typed("NaN", "double"))
  assert_round_trips(typed("+", "integer"))
}

pub fn literals_whose_bare_form_has_another_datatype_round_trip_test() {
  assert_round_trips(typed("1", "double"))
  assert_round_trips(typed("1", "decimal"))
  assert_round_trips(typed("1.0", "integer"))
  assert_round_trips(typed("1.0", "double"))
  assert_round_trips(typed("1e3", "decimal"))
  assert_round_trips(typed("1e3", "integer"))
  assert_round_trips(typed("1", "boolean"))
  assert_round_trips(typed("tRuE", "boolean"))
  assert_round_trips(typed("TRUE", "boolean"))
}

pub fn canonical_numbers_and_booleans_stay_bare_test() {
  written_object(typed("42", "integer")) |> should.equal("42")
  written_object(typed("-7", "integer")) |> should.equal("-7")
  written_object(typed("+7", "integer")) |> should.equal("+7")
  written_object(typed("1.5", "decimal")) |> should.equal("1.5")
  written_object(typed("-.5", "decimal")) |> should.equal("-.5")
  written_object(typed("1.5E-3", "double")) |> should.equal("1.5E-3")
  written_object(typed("1.e3", "double")) |> should.equal("1.e3")
  written_object(typed(".5e3", "double")) |> should.equal(".5e3")
  written_object(typed("true", "boolean")) |> should.equal("true")
  written_object(typed("false", "boolean")) |> should.equal("false")
  list.each(
    [
      typed("42", "integer"),
      typed("-.5", "decimal"),
      typed("1.e3", "double"),
      typed(".5e3", "double"),
      typed("false", "boolean"),
    ],
    assert_round_trips,
  )
}

pub fn non_canonical_forms_are_quoted_test() {
  written_object(typed("abc", "integer"))
  |> should.equal("\"abc\"^^<" <> xsd <> "integer>")
  written_object(typed("1", "double"))
  |> should.equal("\"1\"^^<" <> xsd <> "double>")
  written_object(typed("tRuE", "boolean"))
  |> should.equal("\"tRuE\"^^<" <> xsd <> "boolean>")
}

pub fn blank_node_labels_with_dots_round_trip_test() {
  assert_round_trips("_:b.1 <http://e/p> _:b2 .\n")
  assert_round_trips("<http://e/s> <http://e/p> _:b.1 .\n")
  assert_round_trips("_:a.b.c <http://e/p> _:x..y .\n")
  assert_round_trips(
    "<http://e/s> <http://e/p> <<( _:b.1 <http://e/q> _:c.2 )>> .\n",
  )
}

// Lexer -----------------------------------------------------------------------

pub fn blank_node_label_trailing_dot_is_the_terminator_test() {
  let assert Ok(parsed) =
    turtle.parse_graph("_:b.1 <http://e/p> _:b.2.\n_:b.1 <http://e/p> _:c.")
  graph.triples(parsed)
  |> list.map(fn(triple) { triple.object })
  |> list.sort(fn(a, b) { string.compare(string.inspect(a), string.inspect(b)) })
  |> should.equal([
    term.ObjectBlank(term.unsafe_blank_node("b.2")),
    term.ObjectBlank(term.unsafe_blank_node("c")),
  ])
}

pub fn blank_node_identifier_cannot_end_with_dot_test() {
  term.blank_node("b.1") |> should.be_ok
  term.blank_node("b.") |> should.be_error
}

pub fn booleans_are_case_sensitive_test() {
  parsed_object(statement("true")) |> should.equal(literal("true", "boolean"))
  parsed_object(statement("false"))
  |> should.equal(literal("false", "boolean"))
  parsed_object(statement("tRuE")) |> should.be_error
  parsed_object(statement("TRUE")) |> should.be_error
  parsed_object(statement("False")) |> should.be_error
}

pub fn numbers_follow_the_turtle_grammar_test() {
  parsed_object("<http://e/s> <http://e/p> 1.")
  |> should.equal(literal("1", "integer"))
  parsed_object("<http://e/s> <http://e/p> 1.5.")
  |> should.equal(literal("1.5", "decimal"))
  parsed_object(statement(".5")) |> should.equal(literal(".5", "decimal"))
  parsed_object(statement("1.e3")) |> should.equal(literal("1.e3", "double"))
  parsed_object(statement("-1E+2")) |> should.equal(literal("-1E+2", "double"))
  // `1.` is the integer 1 followed by the terminator, so a second '.' is an
  // error rather than the decimal "1.".
  parsed_object(statement("1.")) |> should.be_error
  parsed_object(statement("+")) |> should.be_error
  parsed_object(statement("1e")) |> should.be_error
}

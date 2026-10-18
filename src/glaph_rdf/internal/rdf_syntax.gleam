//// Shared line-level syntax for the N-Triples and N-Quads formats.
////
//// N-Quads is N-Triples plus an optional graph label, so both serializers
//// share one statement parser and one term writer. The parser works on a
//// list of single-codepoint strings rather than byte or grapheme offsets,
//// which keeps it correct for non-ASCII content on every target.
////
//// Implements the W3C RDF 1.2 N-Triples / N-Quads grammar:
//// - `IRIREF` with `UCHAR` escapes (`\uXXXX`, `\UXXXXXXXX`)
//// - `STRING_LITERAL_QUOTE` with `ECHAR` (`\t \b \n \r \f \" \' \\`) and
////   `UCHAR` escapes, optionally followed by `@lang` or `^^<datatype>`
//// - `BLANK_NODE_LABEL`
//// - triple terms `<<( s p o )>>` (the older `<< s p o >>` form is also read)
//// - blank lines, full-line comments and a comment after the final `.`

import glaph_rdf/statement
import glaph_rdf/term
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// The line-based syntax being parsed.
pub type Syntax {
  /// Exactly three terms per statement.
  NTriples
  /// Three terms plus an optional graph label per statement.
  NQuads
}

type Chars =
  List(String)

// Parsing ---------------------------------------------------------------------

/// Splits a document into lines the same way the streaming line reader does:
/// on LF, with one trailing CR removed from each line, so CRLF and LF
/// documents give the same lines (and the same errors).
///
/// ## Examples
/// ```gleam
/// split_lines("a\r\nb\n")
/// // -> ["a", "b", ""]
/// ```
pub fn split_lines(text: String) -> List(String) {
  text
  |> string.split("\n")
  |> list.map(fn(line) {
    case string.ends_with(line, "\r") {
      True -> string.drop_end(line, 1)
      False -> line
    }
  })
}

/// Parse a single line of N-Triples or N-Quads.
///
/// Returns `Ok(None)` for a blank line or a comment line, and
/// `Ok(Some(quad))` for a statement. Statements without a graph label (and
/// every N-Triples statement) are placed in `term.DefaultGraph`.
///
/// ## Examples
/// ```gleam
/// parse_statement("# a comment", NTriples)
/// // -> Ok(None)
///
/// parse_statement("<http://ex.org/s> <http://ex.org/p> \"o\" . # c", NTriples)
/// // -> Ok(Some(Quad(..., graph: term.DefaultGraph)))
///
/// parse_statement("_:a <http://ex.org/p> _:b <http://ex.org/g> .", NQuads)
/// // -> Ok(Some(Quad(..., graph: term.NamedGraph(...))))
/// ```
pub fn parse_statement(
  line: String,
  syntax: Syntax,
) -> Result(Option(statement.Quad), String) {
  case skip_ws(to_chars(line)) {
    [] | ["#", ..] -> Ok(None)
    input -> {
      use #(subject, rest) <- result.try(parse_subject(input))
      use #(predicate, rest) <- result.try(parse_predicate(skip_ws(rest)))
      use #(object, rest) <- result.try(parse_object(skip_ws(rest)))
      use #(graph, rest) <- result.try(parse_graph_label(skip_ws(rest), syntax))
      use rest <- result.try(expect_dot(skip_ws(rest), syntax))
      case skip_ws(rest) {
        [] | ["#", ..] ->
          Ok(
            Some(statement.Quad(
              subject: subject,
              predicate: predicate,
              object: object,
              graph: graph,
            )),
          )
        _ -> Error("Unexpected content after the final '.'")
      }
    }
  }
}

fn to_chars(text: String) -> Chars {
  string.to_utf_codepoints(text)
  |> list.map(fn(codepoint) { string.from_utf_codepoints([codepoint]) })
}

fn skip_ws(input: Chars) -> Chars {
  case input {
    [" ", ..rest] | ["\t", ..rest] | ["\r", ..rest] -> skip_ws(rest)
    _ -> input
  }
}

fn expect_dot(input: Chars, syntax: Syntax) -> Result(Chars, String) {
  case input, syntax {
    [".", ..rest], _ -> Ok(rest)
    [], NTriples -> Error("N-Triples statement must end with a dot (.)")
    [], NQuads -> Error("N-Quads statement must end with a dot (.)")
    [char, ..], NTriples ->
      Error(
        "Expected '.' but found '"
        <> char
        <> "' (an N-Triples statement has exactly three terms)",
      )
    [char, ..], NQuads ->
      Error(
        "Expected '.' but found '"
        <> char
        <> "' (an N-Quads statement has three terms and an optional graph label)",
      )
  }
}

fn parse_subject(input: Chars) -> Result(#(term.Subject, Chars), String) {
  case input {
    ["<", "<", ..] ->
      parse_triple_term(input)
      |> result.map(fn(parsed) { #(term.SubjectTriple(parsed.0), parsed.1) })
    ["<", ..rest] ->
      parse_iri(rest)
      |> result.map(fn(parsed) { #(term.SubjectNamed(parsed.0), parsed.1) })
    ["_", ":", ..rest] ->
      parse_blank_node(rest)
      |> result.map(fn(parsed) { #(term.SubjectBlank(parsed.0), parsed.1) })
    ["\"", ..] -> Error("A literal is not allowed in subject position")
    [] -> Error("Expected a subject term")
    [char, ..] ->
      Error("Unexpected '" <> char <> "' where a subject was expected")
  }
}

fn parse_predicate(input: Chars) -> Result(#(term.Predicate, Chars), String) {
  case input {
    ["<", "<", ..] ->
      Error("A triple term is not allowed in predicate position")
    ["<", ..rest] -> parse_iri(rest)
    [] -> Error("Expected a predicate IRI")
    [char, ..] ->
      Error("Unexpected '" <> char <> "' where a predicate IRI was expected")
  }
}

fn parse_object(input: Chars) -> Result(#(term.Object, Chars), String) {
  case input {
    ["<", "<", ..] ->
      parse_triple_term(input)
      |> result.map(fn(parsed) { #(term.ObjectTriple(parsed.0), parsed.1) })
    ["<", ..rest] ->
      parse_iri(rest)
      |> result.map(fn(parsed) { #(term.ObjectNamed(parsed.0), parsed.1) })
    ["_", ":", ..rest] ->
      parse_blank_node(rest)
      |> result.map(fn(parsed) { #(term.ObjectBlank(parsed.0), parsed.1) })
    ["\"", ..rest] ->
      parse_literal(rest)
      |> result.map(fn(parsed) { #(term.ObjectLiteral(parsed.0), parsed.1) })
    [] | [".", ..] -> Error("Expected an object term")
    [char, ..] ->
      Error("Unexpected '" <> char <> "' where an object was expected")
  }
}

fn parse_graph_label(
  input: Chars,
  syntax: Syntax,
) -> Result(#(term.GraphName, Chars), String) {
  case syntax, input {
    NQuads, ["<", "<", ..] ->
      Error("A triple term is not allowed as a graph label")
    NQuads, ["<", ..rest] ->
      parse_iri(rest)
      |> result.map(fn(parsed) { #(term.NamedGraph(parsed.0), parsed.1) })
    NQuads, ["_", ":", ..rest] ->
      parse_blank_node(rest)
      |> result.map(fn(parsed) { #(term.BlankGraph(parsed.0), parsed.1) })
    _, _ -> Ok(#(term.DefaultGraph, input))
  }
}

/// Parses `<<( s p o )>>` or the older `<< s p o >>`, starting at `<<`.
fn parse_triple_term(
  input: Chars,
) -> Result(#(term.TripleTerm, Chars), String) {
  let #(closing, body) = case input {
    ["<", "<", "(", ..rest] -> #([")", ">", ">"], rest)
    ["<", "<", ..rest] -> #([">", ">"], rest)
    _ -> #([], input)
  }
  use #(subject, rest) <- result.try(parse_subject(skip_ws(body)))
  use #(predicate, rest) <- result.try(parse_predicate(skip_ws(rest)))
  use #(object, rest) <- result.try(parse_object(skip_ws(rest)))
  case strip_prefix(skip_ws(rest), closing) {
    Ok(rest) -> Ok(#(term.triple_term(subject, predicate, object), rest))
    Error(_) ->
      Error("Unclosed triple term: expected '" <> string.concat(closing) <> "'")
  }
}

fn strip_prefix(input: Chars, prefix: Chars) -> Result(Chars, Nil) {
  case prefix, input {
    [], _ -> Ok(input)
    [expected, ..prefix_rest], [char, ..rest] if expected == char ->
      strip_prefix(rest, prefix_rest)
    _, _ -> Error(Nil)
  }
}

/// Parses an `IRIREF` body (after the opening `<`) and validates the IRI.
fn parse_iri(input: Chars) -> Result(#(term.NamedNode, Chars), String) {
  use #(value, rest) <- result.try(read_iri(input, []))
  case term.named_node(value) {
    Ok(node) -> Ok(#(node, rest))
    Error(_) -> Error("Invalid IRI: " <> value)
  }
}

fn read_iri(input: Chars, acc: Chars) -> Result(#(String, Chars), String) {
  case input {
    [">", ..rest] -> Ok(#(string.concat(list.reverse(acc)), rest))
    ["\\", ..] -> {
      use #(char, rest) <- result.try(read_uchar(input))
      read_iri(rest, [char, ..acc])
    }
    [] -> Error("Unterminated IRI: missing '>'")
    [char, ..rest] ->
      case is_forbidden_in_iri(char) {
        True ->
          Error(
            "Invalid character in IRI: "
            <> string.inspect(char)
            <> " (use a \\u escape)",
          )
        False -> read_iri(rest, [char, ..acc])
      }
  }
}

fn is_forbidden_in_iri(char: String) -> Bool {
  case char {
    "<" | ">" | "\"" | "{" | "}" | "|" | "^" | "`" | "\\" -> True
    _ -> codepoint(char) <= 0x20
  }
}

/// Decodes a `UCHAR` escape (`\uXXXX` or `\UXXXXXXXX`) at the head of `input`.
fn read_uchar(input: Chars) -> Result(#(String, Chars), String) {
  case input {
    ["\\", "u", a, b, c, d, ..rest] -> decode_uchar([a, b, c, d], rest)
    ["\\", "U", a, b, c, d, e, f, g, h, ..rest] ->
      decode_uchar([a, b, c, d, e, f, g, h], rest)
    ["\\", char, ..] -> Error("Invalid escape sequence '\\" <> char <> "'")
    _ -> Error("Invalid escape sequence at end of input")
  }
}

fn decode_uchar(
  digits: Chars,
  rest: Chars,
) -> Result(#(String, Chars), String) {
  let escape = string.concat(digits)
  case parse_hex(digits) {
    Ok(value) ->
      case string.utf_codepoint(value) {
        Ok(cp) -> Ok(#(string.from_utf_codepoints([cp]), rest))
        Error(_) ->
          Error("Invalid Unicode escape: not a code point: " <> escape)
      }
    Error(_) -> Error("Invalid Unicode escape: bad hex digits: " <> escape)
  }
}

fn parse_hex(digits: Chars) -> Result(Int, Nil) {
  list.try_fold(digits, 0, fn(acc, digit) {
    use value <- result.map(hex_value(digit))
    acc * 16 + value
  })
}

fn hex_value(digit: String) -> Result(Int, Nil) {
  case digit {
    "0" -> Ok(0)
    "1" -> Ok(1)
    "2" -> Ok(2)
    "3" -> Ok(3)
    "4" -> Ok(4)
    "5" -> Ok(5)
    "6" -> Ok(6)
    "7" -> Ok(7)
    "8" -> Ok(8)
    "9" -> Ok(9)
    "a" | "A" -> Ok(10)
    "b" | "B" -> Ok(11)
    "c" | "C" -> Ok(12)
    "d" | "D" -> Ok(13)
    "e" | "E" -> Ok(14)
    "f" | "F" -> Ok(15)
    _ -> Error(Nil)
  }
}

/// Parses a `BLANK_NODE_LABEL` body (after `_:`).
fn parse_blank_node(input: Chars) -> Result(#(term.BlankNode, Chars), String) {
  let #(label_chars, rest) = list.split_while(input, is_blank_label_char)
  // A label may contain '.' but never ends with one: a trailing '.' is the
  // statement terminator.
  let #(trailing_dots, label_reversed) =
    list.split_while(list.reverse(label_chars), fn(char) { char == "." })
  let label = string.concat(list.reverse(label_reversed))
  let rest = list.append(trailing_dots, rest)
  case label {
    "" -> Error("Empty blank node label")
    _ ->
      case term.blank_node(label) {
        Ok(node) -> Ok(#(node, rest))
        Error(_) -> Error("Invalid blank node identifier: " <> label)
      }
  }
}

fn is_blank_label_char(char: String) -> Bool {
  case char {
    " " | "\t" | "\r" | "\n" | "<" | ">" | "\"" | "(" | ")" | "#" | "^" | "@" ->
      False
    _ -> True
  }
}

/// Parses a `STRING_LITERAL_QUOTE` body (after the opening `"`) plus an
/// optional `@lang` or `^^<datatype>` suffix.
fn parse_literal(input: Chars) -> Result(#(term.Literal, Chars), String) {
  use #(value, rest) <- result.try(read_string(input, []))
  case rest {
    ["^", "^", "<", ..rest] -> {
      use #(datatype, rest) <- result.try(
        parse_iri(rest)
        |> result.map_error(fn(msg) { "Invalid datatype: " <> msg }),
      )
      Ok(#(term.typed_literal(value, datatype), rest))
    }
    ["^", "^", ..] -> Error("Expected a datatype IRI after '^^'")
    ["@", ..rest] -> {
      let #(tag_chars, rest) = list.split_while(rest, is_language_tag_char)
      let tag = string.concat(tag_chars)
      case term.language_tag(tag) {
        Ok(language) -> Ok(#(term.language_literal(value, language), rest))
        Error(_) -> Error("Invalid language tag: " <> tag)
      }
    }
    _ -> Ok(#(term.simple_literal(value), rest))
  }
}

fn read_string(input: Chars, acc: Chars) -> Result(#(String, Chars), String) {
  case input {
    ["\"", ..rest] -> Ok(#(string.concat(list.reverse(acc)), rest))
    ["\\", "t", ..rest] -> read_string(rest, ["\t", ..acc])
    ["\\", "b", ..rest] -> read_string(rest, ["\u{0008}", ..acc])
    ["\\", "n", ..rest] -> read_string(rest, ["\n", ..acc])
    ["\\", "r", ..rest] -> read_string(rest, ["\r", ..acc])
    ["\\", "f", ..rest] -> read_string(rest, ["\u{000C}", ..acc])
    ["\\", "\"", ..rest] -> read_string(rest, ["\"", ..acc])
    ["\\", "'", ..rest] -> read_string(rest, ["'", ..acc])
    ["\\", "\\", ..rest] -> read_string(rest, ["\\", ..acc])
    ["\\", ..] -> {
      use #(char, rest) <- result.try(read_uchar(input))
      read_string(rest, [char, ..acc])
    }
    ["\n", ..] | ["\r", ..] ->
      Error("Unescaped line break in string literal (use \\n or \\r)")
    [char, ..rest] -> read_string(rest, [char, ..acc])
    [] -> Error("Unterminated string literal")
  }
}

fn is_language_tag_char(char: String) -> Bool {
  char == "-" || is_ascii_alphanumeric(char)
}

fn is_ascii_alphanumeric(char: String) -> Bool {
  let cp = codepoint(char)
  { cp >= 0x30 && cp <= 0x39 }
  || { cp >= 0x41 && cp <= 0x5A }
  || { cp >= 0x61 && cp <= 0x7A }
}

fn codepoint(char: String) -> Int {
  case string.to_utf_codepoints(char) {
    [cp, ..] -> string.utf_codepoint_to_int(cp)
    [] -> 0
  }
}

// Serialization ---------------------------------------------------------------

/// Serialize a triple as one N-Triples statement (without a line break).
///
/// ## Examples
/// ```gleam
/// serialize_triple(triple)
/// // -> "<http://ex.org/s> <http://ex.org/p> \"o\" ."
/// ```
pub fn serialize_triple(triple: statement.Triple) -> String {
  let statement.Triple(subject: subject, predicate: predicate, object: object) =
    triple
  serialize_terms(subject, predicate, object) <> " ."
}

/// Serialize a quad as one canonical N-Quads statement (without a line
/// break). Quads in the default graph are written without a graph label,
/// exactly like an N-Triples statement.
///
/// ## Examples
/// ```gleam
/// serialize_quad(quad_in_named_graph)
/// // -> "<http://ex.org/s> <http://ex.org/p> \"o\" <http://ex.org/g> ."
/// serialize_quad(quad_in_default_graph)
/// // -> "<http://ex.org/s> <http://ex.org/p> \"o\" ."
/// ```
pub fn serialize_quad(quad: statement.Quad) -> String {
  let statement.Quad(
    subject: subject,
    predicate: predicate,
    object: object,
    graph: graph,
  ) = quad
  let terms = serialize_terms(subject, predicate, object)
  case graph {
    term.DefaultGraph -> terms <> " ."
    term.NamedGraph(node) -> terms <> " " <> serialize_named_node(node) <> " ."
    term.BlankGraph(node) -> terms <> " " <> serialize_blank_node(node) <> " ."
  }
}

fn serialize_terms(
  subject: term.Subject,
  predicate: term.Predicate,
  object: term.Object,
) -> String {
  serialize_subject(subject)
  <> " "
  <> serialize_named_node(predicate)
  <> " "
  <> serialize_object(object)
}

fn serialize_subject(subject: term.Subject) -> String {
  case subject {
    term.SubjectNamed(node) -> serialize_named_node(node)
    term.SubjectBlank(node) -> serialize_blank_node(node)
    term.SubjectTriple(triple) -> serialize_triple_term(triple)
  }
}

fn serialize_object(object: term.Object) -> String {
  case object {
    term.ObjectNamed(node) -> serialize_named_node(node)
    term.ObjectBlank(node) -> serialize_blank_node(node)
    term.ObjectLiteral(literal) -> serialize_literal(literal)
    term.ObjectTriple(triple) -> serialize_triple_term(triple)
  }
}

fn serialize_triple_term(triple: term.TripleTerm) -> String {
  let term.TripleTerm(subject, predicate, object) = triple
  "<<( " <> serialize_terms(subject, predicate, object) <> " )>>"
}

fn serialize_named_node(node: term.NamedNode) -> String {
  let term.NamedNode(iri) = node
  "<" <> escape_iri(iri) <> ">"
}

fn serialize_blank_node(node: term.BlankNode) -> String {
  let term.BlankNode(id) = node
  "_:" <> id
}

fn serialize_literal(literal: term.Literal) -> String {
  case literal {
    term.SimpleLiteral(value) -> "\"" <> escape_string(value) <> "\""
    term.LanguageTaggedLiteral(value, tag) -> {
      let term.LanguageTag(lang) = tag
      "\"" <> escape_string(value) <> "\"@" <> lang
    }
    term.TypedLiteral(value, datatype) ->
      "\"" <> escape_string(value) <> "\"^^" <> serialize_named_node(datatype)
  }
}

/// Escape a literal's lexical form for `STRING_LITERAL_QUOTE`, following the
/// RDF 1.2 canonical N-Triples rules: `\"`, `\\`, `\n`, `\r`, `\t`, `\b` and
/// `\f` use `ECHAR`, any other control character uses `\uXXXX`, and every
/// other character (including non-ASCII) is written as-is.
///
/// ## Examples
/// ```gleam
/// escape_string("say \"hi\"\n")
/// // -> "say \\\"hi\\\"\\n"
/// ```
pub fn escape_string(value: String) -> String {
  string.to_utf_codepoints(value)
  |> list.map(fn(cp) {
    case string.utf_codepoint_to_int(cp) {
      0x22 -> "\\\""
      0x5C -> "\\\\"
      0x0A -> "\\n"
      0x0D -> "\\r"
      0x09 -> "\\t"
      0x08 -> "\\b"
      0x0C -> "\\f"
      code if code < 0x20 || code == 0x7F -> uchar(code)
      _ -> string.from_utf_codepoints([cp])
    }
  })
  |> string.concat
}

/// Escape an IRI for `IRIREF`. Characters the grammar forbids inside `<...>`
/// (controls, space, `<>"{}|^` backtick and backslash) are written as
/// `\uXXXX`; everything else is written as-is.
///
/// ## Examples
/// ```gleam
/// escape_iri("http://ex.org/a b")
/// // -> "http://ex.org/a\\u0020b"
/// ```
pub fn escape_iri(iri: String) -> String {
  string.to_utf_codepoints(iri)
  |> list.map(fn(cp) {
    let char = string.from_utf_codepoints([cp])
    case is_forbidden_in_iri(char) {
      True -> uchar(string.utf_codepoint_to_int(cp))
      False -> char
    }
  })
  |> string.concat
}

fn uchar(code: Int) -> String {
  "\\u" <> string.pad_start(string.uppercase(int.to_base16(code)), 4, "0")
}

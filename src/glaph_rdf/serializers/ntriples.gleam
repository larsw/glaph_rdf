//// N-Triples RDF serialization following W3C N-Triples specification.
////
//// N-Triples is a line-based, plain text format for encoding RDF graphs.
//// Each line represents a single RDF triple with no abbreviations or shortcuts.
//// This makes it ideal for large-scale data processing and streaming applications.
//// Supports RDF-star quoted triples with `<<( ... )>>` syntax.

import glaph_rdf/graph
import glaph_rdf/statement
import glaph_rdf/term
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// Error information from N-Triples parsing operations.
///
/// Contains detailed error information including a descriptive message
/// and the line number where the error occurred in the input text.
/// This enables precise error reporting for debugging N-Triples syntax issues.
pub type NTriplesError {
  NTriplesError(message: String, line: Int)
}

/// A complete N-Triples document containing RDF triples.
///
/// Represents a parsed or serializable N-Triples document. N-Triples format
/// is simpler than Turtle - it contains only triples with no base IRI or
/// prefix declarations. Each triple is on its own line ending with a period.
pub type NTriplesDocument {
  NTriplesDocument(graph: graph.Graph)
}

/// Parse an N-Triples document from text into a structured representation.
///
/// Parses N-Triples syntax with one triple per line. Supports all RDF term
/// types including IRIs, blank nodes, literals with datatypes/languages,
/// and RDF-star quoted triples with `<<( ... )>>` syntax. Returns detailed
/// error information with line numbers on parse failures.
///
/// ## Examples
/// ```gleam
/// let nt_text = "<http://example.org/alice> <http://xmlns.com/foaf/0.1/name> \"Alice\" .
///                <http://example.org/bob> <http://xmlns.com/foaf/0.1/age> \"25\"^^<http://www.w3.org/2001/XMLSchema#integer> ."
/// 
/// case ntriples.parse(nt_text) {
///   Ok(document) -> {
///     let triple_count = graph.size(document.graph)
///   }
///   Error(ntriples.NTriplesError(message, line)) -> {
///     // Handle parsing error with specific line number
///   }
/// }
/// ```
pub fn parse(text: String) -> Result(NTriplesDocument, NTriplesError) {
  let lines = string.split(text, "\n")
  parse_lines(lines, 1, graph.new())
  |> result.map(NTriplesDocument)
}

/// Parse an N-Triples document and extract only the RDF graph content.
///
/// Convenience function that parses N-Triples text and returns just the RDF
/// graph. Useful when you only need the actual RDF data without the document
/// wrapper.
///
/// ## Examples
/// ```gleam
/// case ntriples.parse_graph(nt_text) {
///   Ok(rdf_graph) -> {
///     let triples = graph.triples(rdf_graph)
///   }
///   Error(error) -> // Handle parsing error
/// }
/// ```
pub fn parse_graph(text: String) -> Result(graph.Graph, NTriplesError) {
  parse(text)
  |> result.map(fn(doc) { doc.graph })
}

/// Serialize an N-Triples document to N-Triples format text.
///
/// Converts a structured N-Triples document back to valid N-Triples syntax
/// text. Each triple appears on its own line with full IRI notation and
/// proper escaping. RDF-star quoted triples are serialized with `<<( ... )>>`
/// syntax. Output is compliant with W3C N-Triples specification.
///
/// ## Examples
/// ```gleam
/// let nt_text = ntriples.serialize(my_document)
/// 
/// // Result might look like:
/// // <http://example.org/alice> <http://xmlns.com/foaf/0.1/name> "Alice" .
/// // <http://example.org/bob> <http://xmlns.com/foaf/0.1/age> "25"^^<http://www.w3.org/2001/XMLSchema#integer> .
/// ```
pub fn serialize(document: NTriplesDocument) -> String {
  serialize_graph(document.graph)
}

/// Serialize an RDF graph to N-Triples format text.
///
/// Convenience function that directly serializes an RDF graph to N-Triples
/// text without requiring a document wrapper. Each triple is written on its
/// own line with complete IRI notation and appropriate escaping.
///
/// ## Examples
/// ```gleam
/// let nt_text = ntriples.serialize_graph(my_rdf_graph)
/// ```
pub fn serialize_graph(rdf_graph: graph.Graph) -> String {
  graph.triples(rdf_graph)
  |> list.map(serialize_triple)
  |> string.join("\n")
  |> fn(content) {
    case string.is_empty(content) {
      True -> ""
      False -> content <> "\n"
    }
  }
}

// Internal parsing functions

fn parse_lines(
  lines: List(String),
  line_num: Int,
  acc_graph: graph.Graph,
) -> Result(graph.Graph, NTriplesError) {
  case lines {
    [] -> Ok(acc_graph)
    [line, ..rest] -> {
      let trimmed = string.trim(line)
      case trimmed {
        "" -> parse_lines(rest, line_num + 1, acc_graph)
        _ ->
          case parse_line(trimmed, line_num) {
            Ok(triple) ->
              parse_lines(rest, line_num + 1, graph.add(acc_graph, triple))
            Error(error) -> Error(error)
          }
      }
    }
  }
}

fn parse_line(
  line: String,
  line_num: Int,
) -> Result(statement.Triple, NTriplesError) {
  // Check for required trailing dot
  case string.ends_with(line, " .") {
    True -> {
      let content = string.drop_end(line, 2)
      case parse_triple_content(content) {
        Ok(triple) -> Ok(triple)
        Error(msg) -> Error(NTriplesError(msg, line_num))
      }
    }
    False ->
      case string.ends_with(line, ".") {
        True -> {
          let content = string.drop_end(line, 1)
          case parse_triple_content(content) {
            Ok(triple) -> Ok(triple)
            Error(msg) -> Error(NTriplesError(msg, line_num))
          }
        }
        False ->
          Error(NTriplesError(
            "N-Triples statement must end with a dot (.)",
            line_num,
          ))
      }
  }
}

fn parse_triple_content(content: String) -> Result(statement.Triple, String) {
  case parse_subject_predicate_object(content) {
    Ok(#(subject_str, predicate_str, object_str)) -> {
      use subject <- result.try(parse_term_as_subject(subject_str))
      use predicate <- result.try(parse_iri_ref(predicate_str))
      use object <- result.try(parse_term_as_object(object_str))

      Ok(statement.Triple(
        subject: subject,
        predicate: predicate,
        object: object,
      ))
    }
    Error(msg) -> Error(msg)
  }
}

fn parse_subject_predicate_object(
  content: String,
) -> Result(#(String, String, String), String) {
  // Handle RDF-star quoted triples in subject position
  case string.starts_with(content, "<<(") {
    True -> parse_with_quoted_triple_subject(content)
    False -> {
      // Check for quoted triple in object position
      case string.contains(content, "<<(") {
        True -> parse_with_quoted_triple_object(content)
        False -> {
          let parts = tokenize_triple(content)
          case parts {
            [subject, predicate, object] -> Ok(#(subject, predicate, object))
            _ ->
              Error(
                "Expected exactly three terms (subject, predicate, object), got "
                <> string.inspect(list.length(parts)),
              )
          }
        }
      }
    }
  }
}

fn parse_with_quoted_triple_subject(
  content: String,
) -> Result(#(String, String, String), String) {
  case find_quoted_triple_end(content, 0) {
    Some(end_pos) -> {
      let subject = string.slice(content, 0, end_pos + 3)
      let remaining = string.trim_start(string.drop_start(content, end_pos + 3))

      let parts = tokenize_triple(remaining)
      case parts {
        [predicate, object] -> Ok(#(subject, predicate, object))
        _ -> Error("Expected predicate and object after quoted triple subject")
      }
    }
    None -> Error("Unclosed quoted triple in subject position")
  }
}

fn parse_with_quoted_triple_object(
  content: String,
) -> Result(#(String, String, String), String) {
  // Find where the quoted triple starts
  case find_quoted_triple_start(content, 0) {
    Some(start_pos) -> {
      // Find where the quoted triple ends
      case find_quoted_triple_end(content, start_pos + 3) {
        Some(end_pos) -> {
          let before_quoted = string.slice(content, 0, start_pos) |> string.trim
          let quoted_object =
            string.slice(content, start_pos, end_pos - start_pos + 3)

          // Parse the part before the quoted triple to get subject and predicate
          let parts = tokenize_triple(before_quoted)
          case parts {
            [subject, predicate] -> Ok(#(subject, predicate, quoted_object))
            _ ->
              Error(
                "Expected subject and predicate before quoted triple object",
              )
          }
        }
        None -> Error("Unclosed quoted triple in object position")
      }
    }
    None -> Error("Quoted triple not found in object position")
  }
}

fn find_quoted_triple_start(text: String, pos: Int) -> Option(Int) {
  case string.slice(text, pos, 3) {
    "<<(" -> Some(pos)
    _ ->
      case pos >= string.length(text) - 3 {
        True -> None
        False -> find_quoted_triple_start(text, pos + 1)
      }
  }
}

fn find_quoted_triple_end(text: String, pos: Int) -> Option(Int) {
  case string.slice(text, pos, 3) {
    ")>>" -> Some(pos)
    _ ->
      case pos >= string.length(text) - 3 {
        True -> None
        False -> find_quoted_triple_end(text, pos + 1)
      }
  }
}

fn tokenize_triple(content: String) -> List(String) {
  tokenize_loop(string.to_graphemes(content), [], "", False, False, 0)
  |> list.reverse
  |> list.filter(fn(token) { !string.is_empty(token) })
}

fn tokenize_loop(
  chars: List(String),
  tokens: List(String),
  current: String,
  in_iri: Bool,
  in_literal: Bool,
  quote_depth: Int,
) -> List(String) {
  case chars {
    [] -> {
      case string.is_empty(current) {
        True -> tokens
        False -> [current, ..tokens]
      }
    }
    [char, ..rest] -> {
      case char, in_iri, in_literal, quote_depth {
        "<", False, False, 0 -> {
          // Check for quoted triple start
          case string.join([char, ..list.take(rest, 3)], "") {
            "<<(" ->
              tokenize_loop(rest, tokens, current <> char, False, False, 1)
            _ ->
              tokenize_loop(
                rest,
                tokens,
                current <> char,
                True,
                False,
                quote_depth,
              )
          }
        }
        ">", True, False, 0 ->
          tokenize_loop(
            rest,
            [current <> char, ..tokens],
            "",
            False,
            False,
            quote_depth,
          )
        ")", False, False, _ if quote_depth > 0 -> {
          // Check for quoted triple end
          case string.join([char, ..list.take(rest, 2)], "") {
            ")>>" ->
              tokenize_loop(
                list.drop(rest, 2),
                [current <> ")>>", ..tokens],
                "",
                False,
                False,
                quote_depth - 1,
              )
            _ ->
              tokenize_loop(
                rest,
                tokens,
                current <> char,
                in_iri,
                in_literal,
                quote_depth,
              )
          }
        }
        "\"", False, False, _ ->
          tokenize_loop(rest, tokens, current <> char, False, True, quote_depth)
        "\"", False, True, _ ->
          tokenize_loop(
            rest,
            tokens,
            current <> char,
            False,
            False,
            quote_depth,
          )
        " ", False, False, 0 -> {
          case string.is_empty(current) {
            True ->
              tokenize_loop(
                rest,
                tokens,
                current,
                in_iri,
                in_literal,
                quote_depth,
              )
            False ->
              tokenize_loop(
                rest,
                [current, ..tokens],
                "",
                in_iri,
                in_literal,
                quote_depth,
              )
          }
        }
        _, _, _, _ ->
          tokenize_loop(
            rest,
            tokens,
            current <> char,
            in_iri,
            in_literal,
            quote_depth,
          )
      }
    }
  }
}

fn parse_term_as_subject(term_str: String) -> Result(term.Subject, String) {
  case parse_term(term_str) {
    Ok(parsed_term) ->
      case term.subject_from_term(parsed_term) {
        Ok(subject) -> Ok(subject)
        Error(_) -> Error("Invalid term in subject position: " <> term_str)
      }
    Error(msg) -> Error(msg)
  }
}

fn parse_term_as_object(term_str: String) -> Result(term.Object, String) {
  case parse_term(term_str) {
    Ok(parsed_term) -> Ok(term.object_from_term(parsed_term))
    Error(msg) -> Error(msg)
  }
}

fn parse_term(term_str: String) -> Result(term.Term, String) {
  // Check for quoted triple first before checking for plain IRI
  case string.starts_with(term_str, "<<(") {
    True -> parse_quoted_triple(term_str)
    False -> {
      case string.first(term_str) {
        Ok("<") ->
          case string.ends_with(term_str, ">") {
            True -> parse_iri_ref(term_str) |> result.map(term.NamedTerm)
            False -> Error("Unrecognized term format: " <> term_str)
          }
        Ok("_") ->
          case string.starts_with(term_str, "_:") {
            True -> parse_blank_node(term_str)
            False -> Error("Unrecognized term format: " <> term_str)
          }
        Ok("\"") -> parse_literal(term_str)
        Ok(_) -> Error("Unrecognized term format: " <> term_str)
        Error(_) -> Error("Empty term string")
      }
    }
  }
}

fn parse_iri_ref(iri_str: String) -> Result(term.NamedNode, String) {
  case string.starts_with(iri_str, "<") && string.ends_with(iri_str, ">") {
    True -> {
      let iri_content =
        iri_str
        |> string.drop_start(1)
        |> string.drop_end(1)
        |> unescape_iri

      case term.named_node(iri_content) {
        Ok(node) -> Ok(node)
        Error(_) -> Error("Invalid IRI: " <> iri_content)
      }
    }
    False -> Error("IRI must be enclosed in angle brackets: " <> iri_str)
  }
}

fn parse_blank_node(blank_str: String) -> Result(term.Term, String) {
  case string.starts_with(blank_str, "_:") {
    True -> {
      let identifier = string.drop_start(blank_str, 2)
      case term.blank_node(identifier) {
        Ok(node) -> Ok(term.BlankTerm(node))
        Error(_) -> Error("Invalid blank node identifier: " <> identifier)
      }
    }
    False -> Error("Blank node must start with '_:': " <> blank_str)
  }
}

fn parse_literal(literal_str: String) -> Result(term.Term, String) {
  case parse_string_literal(literal_str) {
    Ok(#(value, remainder)) -> {
      case remainder {
        "" -> Ok(term.LiteralTerm(term.simple_literal(value)))
        _ -> {
          case string.starts_with(remainder, "^^") {
            True -> {
              let datatype_str = string.drop_start(remainder, 2)
              case parse_iri_ref(datatype_str) {
                Ok(datatype) ->
                  Ok(term.LiteralTerm(term.typed_literal(value, datatype)))
                Error(msg) -> Error("Invalid datatype: " <> msg)
              }
            }
            False -> {
              case string.starts_with(remainder, "@") {
                True -> {
                  let lang_str = string.drop_start(remainder, 1)
                  case term.language_tag(lang_str) {
                    Ok(lang_tag) ->
                      Ok(
                        term.LiteralTerm(term.language_literal(value, lang_tag)),
                      )
                    Error(_) -> Error("Invalid language tag: " <> lang_str)
                  }
                }
                False -> Error("Invalid literal format: " <> literal_str)
              }
            }
          }
        }
      }
    }
    Error(msg) -> Error(msg)
  }
}

fn parse_quoted_triple(triple_str: String) -> Result(term.Term, String) {
  case
    string.starts_with(triple_str, "<<(") && string.ends_with(triple_str, ")>>")
  {
    True -> {
      let inner_content =
        triple_str
        |> string.drop_start(3)
        |> string.drop_end(3)
        |> string.trim

      case parse_triple_content(inner_content) {
        Ok(triple) -> {
          let statement.Triple(
            subject: subject,
            predicate: predicate,
            object: object,
          ) = triple
          let quoted_triple = term.triple_term(subject, predicate, object)
          Ok(term.QuotedTripleTerm(quoted_triple))
        }
        Error(msg) -> Error("Invalid quoted triple: " <> msg)
      }
    }
    False ->
      Error("Quoted triple must be enclosed in <<( ... )>>: " <> triple_str)
  }
}

fn parse_string_literal(
  literal_str: String,
) -> Result(#(String, String), String) {
  case string.starts_with(literal_str, "\"") {
    True -> {
      case find_string_end(literal_str, 1) {
        Some(end_pos) -> {
          let value =
            literal_str
            |> string.slice(1, end_pos - 1)
            |> unescape_string
          let remainder = string.drop_start(literal_str, end_pos + 1)
          Ok(#(value, remainder))
        }
        None -> Error("Unterminated string literal: " <> literal_str)
      }
    }
    False -> Error("String literal must start with quote: " <> literal_str)
  }
}

fn find_string_end(text: String, pos: Int) -> Option(Int) {
  case string.slice(text, pos, 1) {
    "\"" -> {
      // Check if it's escaped
      case count_preceding_backslashes(text, pos) % 2 {
        0 -> Some(pos)
        _ -> find_string_end(text, pos + 1)
      }
    }
    "" -> None
    _ -> find_string_end(text, pos + 1)
  }
}

fn count_preceding_backslashes(text: String, pos: Int) -> Int {
  count_backslashes_loop(text, pos - 1, 0)
}

fn count_backslashes_loop(text: String, pos: Int, count: Int) -> Int {
  case pos < 0 {
    True -> count
    False ->
      case string.slice(text, pos, 1) {
        "\\" -> count_backslashes_loop(text, pos - 1, count + 1)
        _ -> count
      }
  }
}

// Serialization functions

fn serialize_triple(triple: statement.Triple) -> String {
  let statement.Triple(subject: subject, predicate: predicate, object: object) =
    triple

  serialize_subject(subject)
  <> " "
  <> serialize_predicate(predicate)
  <> " "
  <> serialize_object(object)
  <> " ."
}

fn serialize_subject(subject: term.Subject) -> String {
  case subject {
    term.SubjectNamed(node) -> serialize_named_node(node)
    term.SubjectBlank(node) -> serialize_blank_node(node)
    term.SubjectTriple(triple) -> serialize_quoted_triple(triple)
  }
}

fn serialize_predicate(predicate: term.Predicate) -> String {
  serialize_named_node(predicate)
}

fn serialize_object(object: term.Object) -> String {
  case object {
    term.ObjectNamed(node) -> serialize_named_node(node)
    term.ObjectBlank(node) -> serialize_blank_node(node)
    term.ObjectLiteral(literal) -> serialize_literal(literal)
    term.ObjectTriple(triple) -> serialize_quoted_triple(triple)
  }
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

fn serialize_quoted_triple(triple: term.TripleTerm) -> String {
  let term.TripleTerm(subject, predicate, object) = triple
  "<<( "
  <> serialize_subject(subject)
  <> " "
  <> serialize_predicate(predicate)
  <> " "
  <> serialize_object(object)
  <> " )>>"
}

// String escaping functions

fn escape_string(text: String) -> String {
  text
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
  |> string.replace("\n", "\\n")
  |> string.replace("\r", "\\r")
  |> string.replace("\t", "\\t")
}

fn unescape_string(text: String) -> String {
  text
  |> string.replace("\\n", "\n")
  |> string.replace("\\r", "\r")
  |> string.replace("\\t", "\t")
  |> string.replace("\\\"", "\"")
  |> string.replace("\\\\", "\\")
}

fn escape_iri(iri: String) -> String {
  // N-Triples requires escaping of certain characters in IRIs
  iri
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
  |> string.replace("\n", "\\n")
  |> string.replace("\r", "\\r")
  |> string.replace("\t", "\\t")
}

fn unescape_iri(iri: String) -> String {
  iri
  |> string.replace("\\n", "\n")
  |> string.replace("\\r", "\r")
  |> string.replace("\\t", "\t")
  |> string.replace("\\\"", "\"")
  |> string.replace("\\\\", "\\")
}

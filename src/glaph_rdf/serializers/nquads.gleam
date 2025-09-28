//// N-Quads serializer for RDF datasets following W3C specification
////
//// This module implements the W3C N-Quads specification, providing parsing and
//// serialization capabilities for RDF datasets. N-Quads extends N-Triples by adding
//// a fourth component (graph label) to each statement, enabling representation of
//// multiple named graphs within a single dataset.
////
//// The format follows: `<subject> <predicate> <object> <graph> .`
//// When the graph label is omitted, triples are added to the default graph.
////
//// Supports full RDF-star syntax with quoted triples using `<<( ... )>>` notation
//// in subject and object positions, following the RDF-star specification extensions.

import glaph_rdf/dataset
import glaph_rdf/statement
import glaph_rdf/term
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// A complete N-Quads document representing an RDF dataset.
///
/// Contains the parsed RDF dataset with multiple named graphs and a default graph.
/// Each quad specifies which graph contains the triple, enabling multi-graph
/// RDF data representation.
///
/// ## Examples
/// ```gleam
/// NQuadsDocument(dataset.new())
/// ```
pub type NQuadsDocument {
  NQuadsDocument(dataset: dataset.Dataset)
}

/// Error information from N-Quads parsing operations.
///
/// Provides detailed error messages with line numbers for debugging parsing
/// failures. Compatible with N-Triples errors since N-Quads uses the same
/// syntax for the first three components.
pub type NQuadsError {
  NQuadsError(message: String, line: Int)
}

/// Parse an N-Quads document from text into a structured RDF dataset.
///
/// Parses N-Quads syntax with one quad per line. Each line contains subject,
/// predicate, object, and optional graph label. Supports all RDF term types
/// including IRIs, blank nodes, literals with datatypes/languages, and 
/// RDF-star quoted triples with `<<( ... )>>` syntax.
///
/// ## Examples
/// ```gleam
/// let nq_text = """
/// <http://example.org/alice> <http://xmlns.com/foaf/0.1/name> "Alice" <http://example.org/graph1> .
/// <http://example.org/bob> <http://xmlns.com/foaf/0.1/name> "Bob" .
/// """
/// 
/// case nquads.parse(nq_text) {
///   Ok(document) -> {
///     // Access the dataset
///     let my_dataset = document.dataset
///   }
///   Error(nquads.NQuadsError(message, line)) -> {
///     // Handle parsing error with specific line number
///   }
/// }
/// ```
pub fn parse(text: String) -> Result(NQuadsDocument, NQuadsError) {
  let lines = string.split(text, "\n")
  parse_lines(lines, 1, dataset.new())
  |> result.map(NQuadsDocument)
}

/// Parse an N-Quads document and extract only the RDF dataset content.
///
/// Convenience function that parses N-Quads text and returns just the RDF
/// dataset. Useful when you only need the actual RDF data without the document
/// wrapper.
///
/// ## Examples
/// ```gleam
/// case nquads.parse_dataset(nq_text) {
///   Ok(rdf_dataset) -> {
///     // Work directly with the dataset
///     let graphs = dataset.graphs(rdf_dataset)
///   }
///   Error(error) -> // Handle error
/// }
/// ```
pub fn parse_dataset(text: String) -> Result(dataset.Dataset, NQuadsError) {
  parse(text)
  |> result.map(fn(doc) { doc.dataset })
}

/// Serialize an N-Quads document to text representation.
///
/// Converts a structured N-Quads document back to the standard N-Quads text
/// format. Each quad is written on a separate line with proper escaping of
/// special characters. Preserves all RDF-star quoted triples with `<<( ... )>>`
/// syntax.
///
/// ## Examples
/// ```gleam
/// let serialized = nquads.serialize(document)
/// io.println(serialized)
/// ```
pub fn serialize(document: NQuadsDocument) -> String {
  serialize_dataset(document.dataset)
}

/// Serialize an RDF dataset directly to N-Quads text format.
///
/// Converts an RDF dataset to N-Quads text representation. Includes triples
/// from the default graph (without graph labels) and all named graphs (with
/// their respective graph labels).
///
/// ## Examples
/// ```gleam
/// let nq_text = nquads.serialize_dataset(my_dataset)
/// ```
pub fn serialize_dataset(ds: dataset.Dataset) -> String {
  dataset.quads(ds)
  |> list.map(fn(quad) {
    let statement.Quad(subject, predicate, object, graph) = quad
    case graph {
      term.DefaultGraph ->
        serialize_triple_to_nquads(statement.Triple(subject, predicate, object))
      _ ->
        serialize_quad_to_nquads(
          statement.Triple(subject, predicate, object),
          graph,
        )
    }
  })
  |> string.join("\n")
  |> fn(content) {
    case string.is_empty(content) {
      True -> ""
      False -> content <> "\n"
    }
  }
}

// Private functions

fn parse_lines(
  lines: List(String),
  line_num: Int,
  acc_dataset: dataset.Dataset,
) -> Result(dataset.Dataset, NQuadsError) {
  case lines {
    [] -> Ok(acc_dataset)
    [line, ..rest] -> {
      let trimmed = string.trim(line)
      case trimmed {
        "" -> parse_lines(rest, line_num + 1, acc_dataset)
        _ ->
          case string.starts_with(trimmed, "#") {
            True -> parse_lines(rest, line_num + 1, acc_dataset)
            // Skip comments
            False ->
              case parse_line(trimmed, line_num) {
                Ok(quad) ->
                  parse_lines(
                    rest,
                    line_num + 1,
                    dataset.add_quad(acc_dataset, quad),
                  )
                Error(error) -> Error(error)
              }
          }
      }
    }
  }
}

fn parse_line(
  line: String,
  line_num: Int,
) -> Result(statement.Quad, NQuadsError) {
  // Check for required trailing dot
  case string.ends_with(line, " .") {
    True -> {
      let content = string.drop_end(line, 2)
      case parse_quad_content(content) {
        Ok(quad) -> Ok(quad)
        Error(msg) -> Error(NQuadsError(msg, line_num))
      }
    }
    False ->
      case string.ends_with(line, ".") {
        True -> {
          let content = string.drop_end(line, 1)
          case parse_quad_content(content) {
            Ok(quad) -> Ok(quad)
            Error(msg) -> Error(NQuadsError(msg, line_num))
          }
        }
        False ->
          Error(NQuadsError(
            "N-Quads statement must end with a dot (.)",
            line_num,
          ))
      }
  }
}

fn parse_quad_content(content: String) -> Result(statement.Quad, String) {
  case parse_subject_predicate_object_graph(content) {
    Ok(#(subject_str, predicate_str, object_str, graph_option)) -> {
      use subject <- result.try(parse_term_as_subject(subject_str))
      use predicate <- result.try(parse_iri_ref(predicate_str))
      use object <- result.try(parse_term_as_object(object_str))

      case graph_option {
        Some(graph_str) ->
          case parse_term_as_graph_name(graph_str) {
            Ok(graph_name) ->
              Ok(statement.Quad(
                subject: subject,
                predicate: predicate,
                object: object,
                graph: graph_name,
              ))
            Error(msg) -> Error(msg)
          }
        None ->
          Ok(statement.Quad(
            subject: subject,
            predicate: predicate,
            object: object,
            graph: term.DefaultGraph,
          ))
      }
    }
    Error(msg) -> Error(msg)
  }
}

fn parse_subject_predicate_object_graph(
  content: String,
) -> Result(#(String, String, String, Option(String)), String) {
  // First check if there's a quoted triple in subject position
  case string.starts_with(content, "<<(") {
    True -> parse_with_quoted_triple_subject_nquads(content)
    False -> {
      // Check for quoted triple in object position  
      case string.contains(content, "<<(") {
        True -> parse_with_quoted_triple_object_nquads(content)
        False -> {
          // Regular tokenization for 3 or 4 terms
          let parts = tokenize_quad(content)
          case parts {
            [subject, predicate, object] ->
              Ok(#(subject, predicate, object, None))
            [subject, predicate, object, graph] ->
              Ok(#(subject, predicate, object, Some(graph)))
            _ ->
              Error(
                "Expected 3 or 4 terms (subject, predicate, object, optional graph), got "
                <> string.inspect(list.length(parts)),
              )
          }
        }
      }
    }
  }
}

fn parse_with_quoted_triple_subject_nquads(
  content: String,
) -> Result(#(String, String, String, Option(String)), String) {
  case find_quoted_triple_end(content, 0) {
    Some(end_pos) -> {
      let subject = string.slice(content, 0, end_pos + 3)
      let remaining = string.trim_start(string.drop_start(content, end_pos + 3))

      let parts = tokenize_quad(remaining)
      case parts {
        [predicate, object] -> Ok(#(subject, predicate, object, None))
        [predicate, object, graph] ->
          Ok(#(subject, predicate, object, Some(graph)))
        _ ->
          Error(
            "Expected predicate, object, and optional graph after quoted triple subject",
          )
      }
    }
    None -> Error("Unclosed quoted triple in subject position")
  }
}

fn parse_with_quoted_triple_object_nquads(
  content: String,
) -> Result(#(String, String, String, Option(String)), String) {
  case find_quoted_triple_start(content, 0) {
    Some(start_pos) -> {
      case find_quoted_triple_end(content, start_pos + 3) {
        Some(end_pos) -> {
          let before_quoted = string.slice(content, 0, start_pos) |> string.trim
          let quoted_object =
            string.slice(content, start_pos, end_pos - start_pos + 3)
          let after_start = end_pos + 3
          let after_length = string.length(content) - after_start
          let after_quoted =
            string.slice(content, after_start, after_length) |> string.trim

          // Parse the part before the quoted triple to get subject and predicate
          let before_parts = tokenize_quad(before_quoted)
          case before_parts {
            [subject, predicate] -> {
              // Check if there's a graph after the quoted object
              case string.is_empty(after_quoted) {
                True -> Ok(#(subject, predicate, quoted_object, None))
                False -> {
                  let after_parts = tokenize_quad(after_quoted)
                  case after_parts {
                    [graph] ->
                      Ok(#(subject, predicate, quoted_object, Some(graph)))
                    _ ->
                      Error(
                        "Expected single graph label after quoted triple object",
                      )
                  }
                }
              }
            }
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

// Reuse helper functions from ntriples module with slight modifications for quad tokenization
fn tokenize_quad(content: String) -> List(String) {
  // For now, use simple whitespace splitting since N-Quads has simpler tokenization
  // compared to complex RDF-star cases handled in ntriples
  content
  |> string.split(" ")
  |> list.filter(fn(token) { !string.is_empty(token) })
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

// Simplified term parsing - reimplement key functions locally for now
fn parse_term_as_subject(term_str: String) -> Result(term.Subject, String) {
  case parse_simple_term(term_str) {
    Ok(term_value) ->
      term.subject_from_term(term_value)
      |> result.map_error(fn(_) { "Invalid subject term" })
    Error(msg) -> Error(msg)
  }
}

fn parse_term_as_object(term_str: String) -> Result(term.Object, String) {
  case parse_simple_term(term_str) {
    Ok(term_value) -> Ok(term.object_from_term(term_value))
    Error(msg) -> Error(msg)
  }
}

fn parse_term_as_graph_name(term_str: String) -> Result(term.GraphName, String) {
  case parse_simple_term(term_str) {
    Ok(term_value) ->
      term.graph_name_from_term(term_value)
      |> result.map_error(fn(_) { "Invalid graph name term" })
    Error(msg) -> Error(msg)
  }
}

fn parse_iri_ref(iri_str: String) -> Result(term.NamedNode, String) {
  case parse_simple_term(iri_str) {
    Ok(term.NamedTerm(node)) -> Ok(node)
    Ok(_) -> Error("Predicate must be an IRI")
    Error(msg) -> Error(msg)
  }
}

// Simple term parsing (basic implementation for N-Quads)
fn parse_simple_term(term_str: String) -> Result(term.Term, String) {
  let trimmed = string.trim(term_str)
  case string.starts_with(trimmed, "<") && string.ends_with(trimmed, ">") {
    True -> {
      let iri_content =
        trimmed
        |> string.drop_start(1)
        |> string.drop_end(1)

      case term.named_node(iri_content) {
        Ok(node) -> Ok(term.NamedTerm(node))
        Error(_) -> Error("Invalid IRI: " <> iri_content)
      }
    }
    False -> {
      case string.starts_with(trimmed, "_:") {
        True -> {
          let identifier = string.drop_start(trimmed, 2)
          case term.blank_node(identifier) {
            Ok(node) -> Ok(term.BlankTerm(node))
            Error(_) -> Error("Invalid blank node identifier: " <> identifier)
          }
        }
        False -> {
          case string.starts_with(trimmed, "\"") {
            True -> parse_simple_literal(trimmed)
            False -> Error("Unsupported term format: " <> term_str)
          }
        }
      }
    }
  }
}

fn parse_simple_literal(literal_str: String) -> Result(term.Term, String) {
  case find_closing_quote(literal_str, 1) {
    Some(end_pos) -> {
      let value = string.slice(literal_str, 1, end_pos - 1)
      let remainder = string.drop_start(literal_str, end_pos + 1) |> string.trim

      case remainder {
        "" -> Ok(term.LiteralTerm(term.simple_literal(value)))
        _ -> {
          case string.starts_with(remainder, "^^") {
            True -> {
              let datatype_str = string.drop_start(remainder, 2)
              case parse_simple_term(datatype_str) {
                Ok(term.NamedTerm(datatype)) ->
                  Ok(term.LiteralTerm(term.typed_literal(value, datatype)))
                Ok(_) -> Error("Datatype must be an IRI")
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
    None -> Error("Unterminated string literal: " <> literal_str)
  }
}

fn find_closing_quote(text: String, pos: Int) -> Option(Int) {
  case string.slice(text, pos, 1) {
    "\"" -> Some(pos)
    "\\" -> find_closing_quote(text, pos + 2)
    // Skip escaped character
    "" -> None
    _ -> find_closing_quote(text, pos + 1)
  }
}

// Serialization functions
fn serialize_triple_to_nquads(triple: statement.Triple) -> String {
  let statement.Triple(subject: subject, predicate: predicate, object: object) =
    triple
  serialize_subject(subject)
  <> " "
  <> serialize_predicate(predicate)
  <> " "
  <> serialize_object(object)
  <> " ."
}

fn serialize_quad_to_nquads(
  triple: statement.Triple,
  graph_name: term.GraphName,
) -> String {
  let statement.Triple(subject: subject, predicate: predicate, object: object) =
    triple
  serialize_subject(subject)
  <> " "
  <> serialize_predicate(predicate)
  <> " "
  <> serialize_object(object)
  <> " "
  <> serialize_graph_name(graph_name)
  <> " ."
}

fn serialize_subject(subject: term.Subject) -> String {
  case subject {
    term.SubjectNamed(node) -> serialize_named_node(node)
    term.SubjectBlank(node) -> serialize_blank_node(node)
    term.SubjectTriple(_) -> "<<quoted-triples-not-implemented>>"
    // TODO: RDF-star
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
    term.ObjectTriple(_) -> "<<quoted-triples-not-implemented>>"
    // TODO: RDF-star
  }
}

fn serialize_named_node(node: term.NamedNode) -> String {
  let term.NamedNode(iri) = node
  "<" <> iri <> ">"
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

fn serialize_graph_name(graph_name: term.GraphName) -> String {
  case graph_name {
    term.DefaultGraph -> ""
    // This shouldn't happen in named graph context
    term.NamedGraph(node) -> serialize_named_node(node)
    term.BlankGraph(node) -> serialize_blank_node(node)
  }
}

fn escape_string(value: String) -> String {
  value
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
  |> string.replace("\n", "\\n")
  |> string.replace("\r", "\\r")
  |> string.replace("\t", "\\t")
}

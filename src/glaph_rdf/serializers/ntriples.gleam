//// N-Triples RDF serialization following W3C N-Triples specification.
////
//// N-Triples is a line-based, plain text format for encoding RDF graphs.
//// Each line represents a single RDF triple with no abbreviations or shortcuts.
//// This makes it ideal for large-scale data processing and streaming applications.
//// Supports RDF-star quoted triples with `<<( ... )>>` syntax.

import glaph_rdf/graph
import glaph_rdf/internal/rdf_syntax
import glaph_rdf/internal/streaming
import glaph_rdf/internal/utf8
import glaph_rdf/statement
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import simplifile

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
  // One leading byte order mark is skipped, as the file readers do; any
  // other U+FEFF is a syntax error.
  let lines = rdf_syntax.split_lines(utf8.strip_bom(text))
  parse_lines(lines, 1, [])
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
  |> list.map(rdf_syntax.serialize_triple)
  |> string.join("\n")
  |> fn(content) {
    case string.is_empty(content) {
      True -> ""
      False -> content <> "\n"
    }
  }
}

/// Parse an N-Triples document from a file into a structured representation.
///
/// Reads an N-Triples file and parses its contents with one triple per line.
/// Supports all RDF term types and RDF-star quoted triples. Returns detailed 
/// error information with line numbers on file read failures or parse errors.
///
/// ## Examples
/// ```gleam
/// case ntriples.parse_file("data/triples.nt") {
///   Ok(document) -> {
///     let triple_count = graph.size(document.graph)
///   }
///   Error(error) -> {
///     // Handle file read or parsing error with line numbers
///   }
/// }
/// ```
pub fn parse_file(path: String) -> Result(NTriplesDocument, NTriplesError) {
  case utf8.read_file(path) {
    Ok(contents) -> parse(contents)
    Error(error) -> {
      let error_msg = case error {
        simplifile.Enoent -> "File not found"
        simplifile.Eacces -> "Permission denied"
        simplifile.Eisdir -> "Path is a directory"
        _ -> "File read error"
      }
      Error(NTriplesError("File error: " <> error_msg <> " (" <> path <> ")", 0))
    }
  }
}

/// Parse an N-Triples file and extract only the RDF graph content.
///
/// Convenience function that reads and parses an N-Triples file, returning 
/// just the RDF graph. Useful when you only need the actual RDF triples 
/// from the file without document wrapper.
///
/// ## Examples
/// ```gleam
/// case ntriples.parse_graph_file("data/simple.nt") {
///   Ok(rdf_graph) -> {
///     let triple_count = graph.size(rdf_graph)
///     // Work with the RDF graph directly
///   }
///   Error(error) -> // Handle file or parsing error
/// }
/// ```
pub fn parse_graph_file(path: String) -> Result(graph.Graph, NTriplesError) {
  parse_file(path)
  |> result.map(fn(doc) { doc.graph })
}

/// Serialize an N-Triples document to a file.
///
/// Converts an N-Triples document to valid N-Triples syntax and writes it 
/// to the specified file. Each triple becomes one line ending with a period.
/// Creates parent directories if they don't exist.
///
/// ## Examples
/// ```gleam
/// let document = NTriplesDocument(graph: my_graph)
/// 
/// case ntriples.serialize_to_file(document, "output/triples.nt") {
///   Ok(Nil) -> // File written successfully
///   Error(error) -> // Handle file write error
/// }
/// ```
pub fn serialize_to_file(
  document: NTriplesDocument,
  path: String,
) -> Result(Nil, NTriplesError) {
  let content = serialize(document)
  case simplifile.write(path, content) {
    Ok(Nil) -> Ok(Nil)
    Error(error) -> {
      let error_msg = case error {
        simplifile.Enoent -> "Directory not found"
        simplifile.Eacces -> "Permission denied"
        simplifile.Enospc -> "No space left on device"
        _ -> "File write error"
      }
      Error(NTriplesError("File error: " <> error_msg <> " (" <> path <> ")", 0))
    }
  }
}

/// Serialize an RDF graph to an N-Triples file.
///
/// Convenience function that directly writes an RDF graph to an N-Triples 
/// file without wrapping in a document. Each triple becomes one line ending 
/// with a period. Creates parent directories if they don't exist.
///
/// ## Examples
/// ```gleam
/// case ntriples.serialize_graph_to_file(my_graph, "output/graph.nt") {
///   Ok(Nil) -> // Graph written to file successfully
///   Error(error) -> // Handle file write error
/// }
/// ```
pub fn serialize_graph_to_file(
  rdf_graph: graph.Graph,
  path: String,
) -> Result(Nil, NTriplesError) {
  serialize_to_file(NTriplesDocument(graph: rdf_graph), path)
}

// Internal parsing functions

/// Parses every line, collecting triples in file order, and builds the graph
/// once with `graph.from_list` (O(n log n) deduplication). The streaming
/// parser builds its graph the same way, so both return equal graphs.
fn parse_lines(
  lines: List(String),
  line_num: Int,
  acc: List(statement.Triple),
) -> Result(graph.Graph, NTriplesError) {
  case lines {
    [] -> Ok(graph.from_list(list.reverse(acc)))
    [line, ..rest] ->
      case rdf_syntax.parse_statement(line, rdf_syntax.NTriples) {
        // Blank line or comment
        Ok(None) -> parse_lines(rest, line_num + 1, acc)
        Ok(Some(quad)) ->
          parse_lines(rest, line_num + 1, [
            statement.triple_from_quad(quad),
            ..acc
          ])
        Error(msg) -> Error(NTriplesError(msg, line_num))
      }
  }
}

// Streaming Operations

/// Fold over the triples of an N-Triples file without holding the file or
/// the triples in memory.
///
/// The file is read one line at a time and `f` is called with each triple in
/// file order (duplicates included). Only the current line and your
/// accumulator are kept, so memory use stays constant regardless of file
/// size. Works on both the Erlang and JavaScript targets.
///
/// Errors use the same `NTriplesError` as `parse_file`: a syntax error has
/// the same message and line number, and file errors (open, read, close)
/// have a `"File error: ..."` message. Invalid UTF-8 is reported with the
/// number of the offending line.
///
/// ## Examples
/// ```gleam
/// // Count the triples of a large file in constant memory
/// case ntriples.streaming_fold_file("large.nt", from: 0, with: fn(count, _) {
///   count + 1
/// }) {
///   Ok(count) -> io.println(int.to_string(count) <> " triples")
///   Error(ntriples.NTriplesError(message, line)) ->
///     io.println(message <> " at line " <> int.to_string(line))
/// }
/// ```
pub fn streaming_fold_file(
  path: String,
  from initial: acc,
  with f: fn(acc, statement.Triple) -> acc,
) -> Result(acc, NTriplesError) {
  use acc, quad <- streaming.fold_statements(
    path,
    rdf_syntax.NTriples,
    initial,
    NTriplesError,
  )
  f(acc, statement.triple_from_quad(quad))
}

/// Parse an N-Triples file by reading it line by line.
///
/// The file text is never loaded as a whole: each line is read and parsed in
/// turn, which works on both the Erlang and JavaScript targets. The resulting
/// graph is still held in memory, so memory use grows with the number of
/// triples. To process a file in constant memory, use `streaming_fold_file`.
///
/// The result is equal (`==`) to what `parse_file` returns for the same file,
/// and errors are the same `NTriplesError` values (see `streaming_fold_file`).
///
/// ## Examples
/// ```gleam
/// case ntriples.streaming_parse_file("large_dataset.nt") {
///   Ok(document) ->
///     io.println(int.to_string(graph.size(document.graph)) <> " triples")
///   Error(ntriples.NTriplesError(message, line)) ->
///     io.println(message <> " at line " <> int.to_string(line))
/// }
/// ```
pub fn streaming_parse_file(
  path: String,
) -> Result(NTriplesDocument, NTriplesError) {
  streaming_fold_file(path, from: [], with: fn(acc, triple) { [triple, ..acc] })
  |> result.map(fn(triples) {
    NTriplesDocument(graph: graph.from_list(list.reverse(triples)))
  })
}

/// Serialize an RDF graph to an N-Triples file, writing it in batches of
/// lines instead of building the whole document as one string first.
///
/// The output is byte-for-byte the same as `serialize_graph`. The file is
/// created or truncated. Errors from writing and from closing the file (where
/// buffered write failures such as a full disk are reported) are returned as
/// an `NTriplesError` with a `"File error: ..."` message and line 0.
///
/// ## Examples
/// ```gleam
/// case ntriples.streaming_serialize_to_file(my_graph, "output.nt") {
///   Ok(Nil) -> io.println("Graph written")
///   Error(ntriples.NTriplesError(message, _)) -> io.println(message)
/// }
/// ```
pub fn streaming_serialize_to_file(
  rdf_graph: graph.Graph,
  path: String,
) -> Result(Nil, NTriplesError) {
  streaming.write_lines(
    path,
    graph.triples(rdf_graph),
    rdf_syntax.serialize_triple,
    NTriplesError,
  )
}

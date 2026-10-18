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
import glaph_rdf/internal/rdf_syntax
import glaph_rdf/internal/streaming
import glaph_rdf/internal/utf8
import glaph_rdf/statement
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import simplifile

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
  // One leading byte order mark is skipped, as the file readers do; any
  // other U+FEFF is a syntax error.
  let lines = rdf_syntax.split_lines(utf8.strip_bom(text))
  parse_lines(lines, 1, [])
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
  |> list.map(rdf_syntax.serialize_quad)
  |> string.join("\n")
  |> fn(content) {
    case string.is_empty(content) {
      True -> ""
      False -> content <> "\n"
    }
  }
}

/// Parse an N-Quads document from a file into a structured representation.
///
/// Reads an N-Quads file and parses its contents with one quad per line.
/// Supports all RDF term types including IRIs, blank nodes, literals with 
/// datatypes/languages, and RDF-star quoted triples. Returns detailed error 
/// information with line numbers on file read failures or parse errors.
///
/// ## Examples
/// ```gleam
/// case nquads.parse_file("data/dataset.nq") {
///   Ok(document) -> {
///     let quad_count = dataset.quad_count(document.dataset)
///   }
///   Error(error) -> {
///     // Handle file read or parsing error with line numbers
///   }
/// }
/// ```
pub fn parse_file(path: String) -> Result(NQuadsDocument, NQuadsError) {
  case utf8.read_file(path) {
    Ok(contents) -> parse(contents)
    Error(error) -> {
      let error_msg = case error {
        simplifile.Enoent -> "File not found"
        simplifile.Eacces -> "Permission denied"
        simplifile.Eisdir -> "Path is a directory"
        _ -> "File read error"
      }
      Error(NQuadsError("File error: " <> error_msg <> " (" <> path <> ")", 0))
    }
  }
}

/// Parse an N-Quads file and extract only the RDF dataset content.
///
/// Convenience function that reads and parses an N-Quads file, returning 
/// just the RDF dataset. Useful when you only need the actual RDF quads 
/// with their named graph structure from the file.
///
/// ## Examples
/// ```gleam
/// case nquads.parse_dataset_file("data/graphs.nq") {
///   Ok(rdf_dataset) -> {
///     let graph_names = dataset.graph_names(rdf_dataset)
///     // Work with the RDF dataset and named graphs directly
///   }
///   Error(error) -> // Handle file or parsing error
/// }
/// ```
pub fn parse_dataset_file(
  path: String,
) -> Result(dataset.Dataset, NQuadsError) {
  parse_file(path)
  |> result.map(fn(doc) { doc.dataset })
}

/// Serialize an N-Quads document to a file.
///
/// Converts an N-Quads document to valid N-Quads syntax and writes it to 
/// the specified file. Each quad becomes one line ending with a period.
/// Creates parent directories if they don't exist.
///
/// ## Examples
/// ```gleam
/// let document = NQuadsDocument(dataset: my_dataset)
/// 
/// case nquads.serialize_to_file(document, "output/dataset.nq") {
///   Ok(Nil) -> // File written successfully
///   Error(error) -> // Handle file write error
/// }
/// ```
pub fn serialize_to_file(
  document: NQuadsDocument,
  path: String,
) -> Result(Nil, NQuadsError) {
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
      Error(NQuadsError("File error: " <> error_msg <> " (" <> path <> ")", 0))
    }
  }
}

/// Serialize an RDF dataset to an N-Quads file.
///
/// Convenience function that directly writes an RDF dataset to an N-Quads 
/// file without wrapping in a document. Each quad becomes one line ending 
/// with a period. Creates parent directories if they don't exist.
///
/// ## Examples
/// ```gleam
/// case nquads.serialize_dataset_to_file(my_dataset, "output/dataset.nq") {
///   Ok(Nil) -> // Dataset written to file successfully
///   Error(error) -> // Handle file write error
/// }
/// ```
pub fn serialize_dataset_to_file(
  ds: dataset.Dataset,
  path: String,
) -> Result(Nil, NQuadsError) {
  serialize_to_file(NQuadsDocument(dataset: ds), path)
}

// Private functions

/// Parses every line, collecting quads in file order, and builds the dataset
/// once with `dataset.from_list` (O(n log n) deduplication). The streaming
/// parser builds its dataset the same way, so both return equal datasets.
fn parse_lines(
  lines: List(String),
  line_num: Int,
  acc: List(statement.Quad),
) -> Result(dataset.Dataset, NQuadsError) {
  case lines {
    [] -> Ok(dataset.from_list(list.reverse(acc)))
    [line, ..rest] ->
      case rdf_syntax.parse_statement(line, rdf_syntax.NQuads) {
        // Blank line or comment
        Ok(None) -> parse_lines(rest, line_num + 1, acc)
        Ok(Some(quad)) -> parse_lines(rest, line_num + 1, [quad, ..acc])
        Error(msg) -> Error(NQuadsError(msg, line_num))
      }
  }
}

// Streaming Operations

/// Fold over the quads of an N-Quads file without holding the file or the
/// quads in memory.
///
/// The file is read one line at a time and `f` is called with each quad in
/// file order (duplicates included). Statements without a graph label are in
/// `term.DefaultGraph`. Only the current line and your accumulator are kept,
/// so memory use stays constant regardless of file size. Works on both the
/// Erlang and JavaScript targets.
///
/// Errors use the same `NQuadsError` as `parse_file`: a syntax error has the
/// same message and line number, and file errors (open, read, close) have a
/// `"File error: ..."` message. Invalid UTF-8 is reported with the number of
/// the offending line.
///
/// ## Examples
/// ```gleam
/// // Count the quads in named graphs in constant memory
/// let count_named = fn(count, quad: statement.Quad) {
///   case quad.graph {
///     term.DefaultGraph -> count
///     _ -> count + 1
///   }
/// }
/// case nquads.streaming_fold_file("large.nq", from: 0, with: count_named) {
///   Ok(count) -> io.println(int.to_string(count) <> " quads in named graphs")
///   Error(nquads.NQuadsError(message, line)) ->
///     io.println(message <> " at line " <> int.to_string(line))
/// }
/// ```
pub fn streaming_fold_file(
  path: String,
  from initial: acc,
  with f: fn(acc, statement.Quad) -> acc,
) -> Result(acc, NQuadsError) {
  streaming.fold_statements(path, rdf_syntax.NQuads, initial, NQuadsError, f)
}

/// Parse an N-Quads file by reading it line by line.
///
/// The file text is never loaded as a whole: each line is read and parsed in
/// turn, which works on both the Erlang and JavaScript targets. The resulting
/// dataset is still held in memory, so memory use grows with the number of
/// quads. To process a file in constant memory, use `streaming_fold_file`.
///
/// The result is equal (`==`) to what `parse_file` returns for the same file,
/// and errors are the same `NQuadsError` values (see `streaming_fold_file`).
///
/// ## Examples
/// ```gleam
/// case nquads.streaming_parse_file("large_dataset.nq") {
///   Ok(document) ->
///     io.println(
///       int.to_string(dataset.quad_count(document.dataset)) <> " quads",
///     )
///   Error(nquads.NQuadsError(message, line)) ->
///     io.println(message <> " at line " <> int.to_string(line))
/// }
/// ```
pub fn streaming_parse_file(
  path: String,
) -> Result(NQuadsDocument, NQuadsError) {
  streaming_fold_file(path, from: [], with: fn(acc, quad) { [quad, ..acc] })
  |> result.map(fn(quads) {
    NQuadsDocument(dataset: dataset.from_list(list.reverse(quads)))
  })
}

/// Serialize an RDF dataset to an N-Quads file, writing it in batches of
/// lines instead of building the whole document as one string first.
///
/// The output is byte-for-byte the same as `serialize_dataset`. The file is
/// created or truncated. Errors from writing and from closing the file (where
/// buffered write failures such as a full disk are reported) are returned as
/// an `NQuadsError` with a `"File error: ..."` message and line 0.
///
/// ## Examples
/// ```gleam
/// case nquads.streaming_serialize_to_file(my_dataset, "output.nq") {
///   Ok(Nil) -> io.println("Dataset written")
///   Error(nquads.NQuadsError(message, _)) -> io.println(message)
/// }
/// ```
pub fn streaming_serialize_to_file(
  ds: dataset.Dataset,
  path: String,
) -> Result(Nil, NQuadsError) {
  streaming.write_lines(
    path,
    dataset.quads(ds),
    rdf_syntax.serialize_quad,
    NQuadsError,
  )
}

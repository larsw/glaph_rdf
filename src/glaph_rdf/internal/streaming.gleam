//// Shared file streaming for the line-based serializers (N-Triples and
//// N-Quads).
////
//// Reading goes through `glaph_rdf/internal/line_reader`, which works on both
//// the Erlang and JavaScript targets. Every function opens and closes the file
//// itself and reports failures through a caller-supplied constructor
//// `fn(message, line) -> e`, so each serializer can return its own error type
//// and `file_streams` types never reach the public API.
////
//// Error conventions, matching `parse_file`/`serialize_to_file`:
////
//// - Open, write and close failures: `"File error: <description> (<path>)"`
////   with line 0.
//// - Read failures: the same message, with the number of the line that could
////   not be read.
//// - Invalid UTF-8: `"File error: Invalid UTF-8 (<path>)"` with the number of
////   the offending line.
//// - Syntax errors: the parser's message and line number, exactly as
////   `parse`/`parse_file` report them.

import file_streams/file_stream.{type FileStream}
import file_streams/file_stream_error.{type FileStreamError}
import glaph_rdf/internal/line_reader.{type LineReader}
import glaph_rdf/internal/rdf_syntax
import glaph_rdf/statement
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

/// Number of statements written per `write_chars` call. Batching keeps the
/// number of system calls low on JavaScript, where writes are not buffered.
const write_batch_size = 256

/// Folds `f` over every statement of the file at `path`, in file order,
/// reading one line at a time. Blank lines and comments are skipped. Stops at
/// the first read or syntax error.
///
/// ## Examples
///
/// ```gleam
/// streaming.fold_statements(
///   "data.nq",
///   rdf_syntax.NQuads,
///   0,
///   NQuadsError,
///   fn(count, _quad) { count + 1 },
/// )
/// // -> Ok(42)
/// ```
pub fn fold_statements(
  path: String,
  syntax: rdf_syntax.Syntax,
  initial: acc,
  make_error: fn(String, Int) -> e,
  f: fn(acc, statement.Quad) -> acc,
) -> Result(acc, e) {
  use stream <- with_stream(file_stream.open_read(path), path, make_error)
  fold_lines(line_reader.new(stream), syntax, initial, f, path, make_error)
}

fn fold_lines(
  reader: LineReader,
  syntax: rdf_syntax.Syntax,
  acc: acc,
  f: fn(acc, statement.Quad) -> acc,
  path: String,
  make_error: fn(String, Int) -> e,
) -> Result(acc, e) {
  case line_reader.next(reader) {
    Ok(#(line, reader)) ->
      case rdf_syntax.parse_statement(line, syntax) {
        Ok(None) -> fold_lines(reader, syntax, acc, f, path, make_error)
        Ok(Some(quad)) ->
          fold_lines(reader, syntax, f(acc, quad), f, path, make_error)
        Error(message) ->
          Error(make_error(message, line_reader.line_number(reader)))
      }
    Error(line_reader.Eof) -> Ok(acc)
    Error(line_reader.InvalidUtf8(line)) ->
      Error(make_error("File error: Invalid UTF-8 (" <> path <> ")", line))
    Error(line_reader.ReadError(error)) ->
      Error(make_error(
        describe(error, path),
        line_reader.line_number(reader) + 1,
      ))
  }
}

/// Writes `to_line(item) <> "\n"` for every item to the file at `path`,
/// creating or truncating it. Write errors and errors reported when the file
/// is closed (for example a delayed `ENOSPC`) are both returned.
///
/// ## Examples
///
/// ```gleam
/// streaming.write_lines(
///   "out.nt",
///   graph.triples(my_graph),
///   rdf_syntax.serialize_triple,
///   NTriplesError,
/// )
/// // -> Ok(Nil)
/// ```
pub fn write_lines(
  path: String,
  items: List(a),
  to_line: fn(a) -> String,
  make_error: fn(String, Int) -> e,
) -> Result(Nil, e) {
  use stream <- with_stream(file_stream.open_write(path), path, make_error)
  items
  |> list.sized_chunk(write_batch_size)
  |> list.try_each(fn(batch) {
    batch
    |> list.map(fn(item) { to_line(item) <> "\n" })
    |> string.concat
    |> file_stream.write_chars(stream, _)
  })
  |> result.map_error(fn(error) { make_error(describe(error, path), 0) })
}

/// Runs `body` with the opened stream and always closes it afterwards. The
/// body's error wins; otherwise a failure to close is reported, because with
/// delayed writes that is where a failed flush shows up.
fn with_stream(
  opened: Result(FileStream, FileStreamError),
  path: String,
  make_error: fn(String, Int) -> e,
  body: fn(FileStream) -> Result(a, e),
) -> Result(a, e) {
  let to_error = fn(error) { make_error(describe(error, path), 0) }
  use stream <- result.try(result.map_error(opened, to_error))
  let outcome = body(stream)
  let closed = file_stream.close(stream)
  case outcome, closed {
    Error(_), _ -> outcome
    Ok(value), Ok(Nil) -> Ok(value)
    Ok(_), Error(error) -> Error(to_error(error))
  }
}

fn describe(error: FileStreamError, path: String) -> String {
  "File error: " <> file_stream_error.describe(error) <> " (" <> path <> ")"
}

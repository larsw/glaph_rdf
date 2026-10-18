//// A portable, constant-memory line reader on top of `file_streams`.
////
//// `file_stream.read_line` is not implemented on the JavaScript target (it
//// always returns `Error(Enotsup)`), so this module reads the stream in
//// fixed-size chunks with `file_stream.read_bytes` (which works on both
//// Erlang and JavaScript) and splits the bytes into lines itself.
////
//// Behaviour, identical on both targets:
////
//// - Lines are split on LF (`\n`, byte `0x0A`). Splitting happens on raw
////   bytes before decoding, which is safe for UTF-8 because `0x0A` never
////   occurs inside a multi-byte sequence. A multi-byte character that
////   straddles a chunk boundary is therefore reassembled correctly.
//// - The returned line never includes the `\n`. A single trailing CR (`\r`)
////   is stripped as well, so CRLF files read the same as LF files.
//// - The last line is returned even when the file does not end with a
////   newline. A file that ends with a newline does not produce an extra empty
////   line at the end. An empty file produces no lines.
//// - Each line is decoded as UTF-8. Invalid UTF-8 is reported as
////   `InvalidUtf8(line)` with the 1-based line number.
//// - A byte order mark (U+FEFF) at the very start of the file is removed.
////   U+FEFF anywhere else, including at the start of a later line, is kept
////   (on JavaScript too, where the standard decoder would drop it).
//// - Memory use is bounded by the chunk size plus the longest line.
////
//// The stream must be readable with `read_bytes`, i.e. opened with
//// `file_stream.open_read` (raw mode) or with the default Latin-1 encoding.
//// This module never opens or closes the stream; the caller owns it.
////
//// ## API
////
//// - `new(stream) -> LineReader` creates a reader with 64 KiB chunks.
//// - `new_with_chunk_size(stream, bytes) -> LineReader` uses a custom chunk
////   size (mainly for tests).
//// - `next(reader) -> Result(#(String, LineReader), LineError)` returns the
////   next line and the updated reader, or `Error(Eof)` once all lines have
////   been returned. `LineReader` is an immutable value: always continue with
////   the reader returned by `next`.
//// - `line_number(reader) -> Int` is the 1-based number of the last line
////   returned by `next` (0 before the first line).
//// - `fold_lines(stream, initial, f)` calls `f(acc, line, line_number)` for
////   every line and stops at the first `Error` returned by `f`, which comes
////   back as `Error(CallbackError(e))`. Read and decoding failures come back
////   as `Error(LineFailure(error))`. Reaching the end of the file is not an
////   error: the final accumulator is returned as `Ok(acc)`.
////
//// ## Examples
////
//// ```gleam
//// use stream <- result.try(file_stream.open_read("data.nt"))
//// let count =
////   line_reader.fold_lines(stream, 0, fn(count, _line, _line_number) {
////     Ok(count + 1)
////   })
//// let _ = file_stream.close(stream)
//// count
//// ```

import file_streams/file_stream.{type FileStream}
import file_streams/file_stream_error.{type FileStreamError}
import glaph_rdf/internal/utf8
import gleam/bit_array
import gleam/list

/// Default number of bytes requested from the stream per read.
const default_chunk_size = 65_536

/// Reads lines from a `FileStream`. Create one with `new` and pull lines with
/// `next`.
pub opaque type LineReader {
  LineReader(
    stream: FileStream,
    chunk_size: Int,
    // Bytes read from the stream that have not been scanned for LF yet.
    buffer: BitArray,
    // Earlier pieces of the current (unterminated) line, most recent first.
    partial: List(BitArray),
    // Number of lines returned so far.
    line: Int,
    // True once the stream has reported end of file.
    at_eof: Bool,
  )
}

/// Errors returned by `next`.
pub type LineError {
  /// All lines have been returned.
  Eof
  /// The underlying stream failed.
  ReadError(error: FileStreamError)
  /// The line with this 1-based number is not valid UTF-8.
  InvalidUtf8(line: Int)
}

/// Errors returned by `fold_lines`.
pub type FoldError(e) {
  /// Reading or decoding a line failed (never `Eof`).
  LineFailure(error: LineError)
  /// The callback returned an error, which stopped the fold.
  CallbackError(error: e)
}

/// Creates a line reader that reads the stream in 64 KiB chunks.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(stream) = file_stream.open_read("data.nt")
/// let reader = line_reader.new(stream)
/// ```
pub fn new(stream: FileStream) -> LineReader {
  new_with_chunk_size(stream, default_chunk_size)
}

/// Creates a line reader that requests `chunk_size` bytes per read. Values
/// below 1 are treated as 1. Mostly useful to exercise chunk boundaries in
/// tests.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(stream) = file_stream.open_read("data.nt")
/// let reader = line_reader.new_with_chunk_size(stream, 4096)
/// ```
pub fn new_with_chunk_size(stream: FileStream, chunk_size: Int) -> LineReader {
  let chunk_size = case chunk_size < 1 {
    True -> 1
    False -> chunk_size
  }
  LineReader(
    stream:,
    chunk_size:,
    buffer: <<>>,
    partial: [],
    line: 0,
    at_eof: False,
  )
}

/// Returns the 1-based number of the last line returned by `next`, or 0 if
/// no line has been returned yet.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(#(_line, reader)) = line_reader.next(line_reader.new(stream))
/// line_reader.line_number(reader)
/// // -> 1
/// ```
pub fn line_number(reader: LineReader) -> Int {
  reader.line
}

/// Reads the next line, without its line terminator (`\n` or `\r\n`).
/// Returns `Error(Eof)` once every line has been returned.
///
/// ## Examples
///
/// ```gleam
/// // data.txt contains "a\r\nb"
/// let reader = line_reader.new(stream)
/// let assert Ok(#("a", reader)) = line_reader.next(reader)
/// let assert Ok(#("b", reader)) = line_reader.next(reader)
/// line_reader.next(reader)
/// // -> Error(line_reader.Eof)
/// ```
pub fn next(reader: LineReader) -> Result(#(String, LineReader), LineError) {
  let LineReader(buffer:, partial:, ..) = reader
  case find_newline(buffer) {
    -1 ->
      case reader.at_eof {
        True ->
          case partial, bit_array.byte_size(buffer) {
            [], 0 -> Error(Eof)
            _, _ -> {
              let bytes = join([buffer, ..partial])
              emit(bytes, LineReader(..reader, buffer: <<>>, partial: []))
            }
          }
        False -> fill(reader)
      }
    index -> {
      let size = bit_array.byte_size(buffer)
      let assert Ok(head) = bit_array.slice(buffer, 0, index)
      let assert Ok(rest) = bit_array.slice(buffer, index + 1, size - index - 1)
      let bytes = case partial {
        [] -> head
        _ -> join([head, ..partial])
      }
      emit(bytes, LineReader(..reader, buffer: rest, partial: []))
    }
  }
}

/// Reads the next chunk from the stream into the reader, then continues
/// with `next`.
fn fill(reader: LineReader) -> Result(#(String, LineReader), LineError) {
  case file_stream.read_bytes(reader.stream, reader.chunk_size) {
    Ok(bytes) -> {
      // The current buffer has no LF, so it belongs to the current line.
      let partial = case bit_array.byte_size(reader.buffer) {
        0 -> reader.partial
        _ -> [reader.buffer, ..reader.partial]
      }
      next(LineReader(..reader, buffer: bytes, partial:))
    }
    Error(file_stream_error.Eof) -> next(LineReader(..reader, at_eof: True))
    Error(error) -> Error(ReadError(error))
  }
}

/// Strips a trailing CR, decodes the line and bumps the line counter. A byte
/// order mark is stripped from the first line only.
fn emit(
  bytes: BitArray,
  reader: LineReader,
) -> Result(#(String, LineReader), LineError) {
  let line = reader.line + 1
  case utf8.decode(detach(strip_cr(bytes))) {
    Ok(text) if line == 1 ->
      Ok(#(utf8.strip_bom(text), LineReader(..reader, line:)))
    Ok(text) -> Ok(#(text, LineReader(..reader, line:)))
    Error(Nil) -> Error(InvalidUtf8(line))
  }
}

fn strip_cr(bytes: BitArray) -> BitArray {
  let size = bit_array.byte_size(bytes)
  case size > 0 && bit_array.slice(bytes, size - 1, 1) == Ok(<<13>>) {
    True -> {
      let assert Ok(stripped) = bit_array.slice(bytes, 0, size - 1)
      stripped
    }
    False -> bytes
  }
}

/// Concatenates line pieces given most recent first.
fn join(pieces_reversed: List(BitArray)) -> BitArray {
  pieces_reversed |> list.reverse |> bit_array.concat
}

/// Calls `f(acc, line, line_number)` for every line of the stream, in order,
/// with 1-based line numbers. Stops at the first error, either from reading
/// (`LineFailure`) or from `f` (`CallbackError`). Only one line is held in
/// memory at a time.
///
/// ## Examples
///
/// ```gleam
/// // data.txt contains "a\nb\n"
/// line_reader.fold_lines(stream, [], fn(acc, line, number) {
///   Ok([#(number, line), ..acc])
/// })
/// // -> Ok([#(2, "b"), #(1, "a")])
/// ```
pub fn fold_lines(
  stream: FileStream,
  initial: acc,
  f: fn(acc, String, Int) -> Result(acc, e),
) -> Result(acc, FoldError(e)) {
  fold_reader(new(stream), initial, f)
}

/// Like `fold_lines`, but starts from an existing reader (for example one
/// created with `new_with_chunk_size`).
///
/// ## Examples
///
/// ```gleam
/// line_reader.new_with_chunk_size(stream, 4096)
/// |> line_reader.fold_reader(0, fn(count, _line, _number) { Ok(count + 1) })
/// // -> Ok(2)
/// ```
pub fn fold_reader(
  reader: LineReader,
  initial: acc,
  f: fn(acc, String, Int) -> Result(acc, e),
) -> Result(acc, FoldError(e)) {
  case next(reader) {
    Ok(#(line, reader)) ->
      case f(initial, line, reader.line) {
        Ok(acc) -> fold_reader(reader, acc, f)
        Error(e) -> Error(CallbackError(e))
      }
    Error(Eof) -> Ok(initial)
    Error(error) -> Error(LineFailure(error))
  }
}

/// Byte index of the first LF in `bytes`, or -1 if there is none.
@external(erlang, "glaph_rdf_line_reader_ffi", "find_newline")
@external(javascript, "./line_reader_ffi.mjs", "find_newline")
fn find_newline(bytes: BitArray) -> Int

/// Copies `bytes` on Erlang so the decoded line does not keep the whole read
/// chunk alive; a no-op on JavaScript.
@external(erlang, "glaph_rdf_line_reader_ffi", "detach")
@external(javascript, "./line_reader_ffi.mjs", "detach")
fn detach(bytes: BitArray) -> BitArray

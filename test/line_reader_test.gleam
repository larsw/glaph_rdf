import file_streams/file_stream
import glaph_rdf/internal/line_reader
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/string
import gleeunit/should
import simplifile

// Helpers --------------------------------------------------------------------

fn path(name: String) -> String {
  "build/tmp_line_reader_" <> name <> ".txt"
}

/// Writes `bytes` to a temporary file, reads every line with the given chunk
/// size, deletes the file and returns the result.
fn read_all(
  name: String,
  bytes: BitArray,
  chunk_size: Int,
) -> Result(List(String), line_reader.LineError) {
  let file = path(name)
  let assert Ok(Nil) = simplifile.write_bits(file, bytes)
  let assert Ok(stream) = file_stream.open_read(file)
  let result = collect(line_reader.new_with_chunk_size(stream, chunk_size), [])
  let assert Ok(Nil) = file_stream.close(stream)
  let assert Ok(Nil) = simplifile.delete(file)
  result
}

fn collect(
  reader: line_reader.LineReader,
  acc: List(String),
) -> Result(List(String), line_reader.LineError) {
  case line_reader.next(reader) {
    Ok(#(line, reader)) -> collect(reader, [line, ..acc])
    Error(line_reader.Eof) -> Ok(list.reverse(acc))
    Error(e) -> Error(e)
  }
}

/// Reads `text` with several chunk sizes (including tiny ones that split
/// lines, CRLF pairs and multi-byte characters) and checks they all agree.
fn lines_of(name: String, text: String) -> List(String) {
  let bytes = bit_array.from_string(text)
  let assert Ok(expected) = read_all(name, bytes, 65_536)
  list.each([1, 2, 3, 5, 7], fn(size) {
    read_all(name <> "_" <> int.to_string(size), bytes, size)
    |> should.equal(Ok(expected))
  })
  expected
}

// Tests ----------------------------------------------------------------------

pub fn lf_lines_test() {
  lines_of("lf", "first\nsecond\nthird\n")
  |> should.equal(["first", "second", "third"])
}

pub fn crlf_lines_test() {
  lines_of("crlf", "first\r\nsecond\r\nthird\r\n")
  |> should.equal(["first", "second", "third"])
}

pub fn mixed_line_endings_test() {
  lines_of("mixed", "a\r\nb\nc\r\n")
  |> should.equal(["a", "b", "c"])
}

pub fn no_trailing_newline_test() {
  lines_of("no_trailing", "first\nlast")
  |> should.equal(["first", "last"])
}

pub fn no_trailing_newline_crlf_test() {
  lines_of("no_trailing_crlf", "first\r\nlast\r")
  |> should.equal(["first", "last"])
}

pub fn single_line_without_newline_test() {
  lines_of("single", "only")
  |> should.equal(["only"])
}

pub fn empty_file_test() {
  lines_of("empty", "")
  |> should.equal([])
}

pub fn empty_lines_test() {
  lines_of("empty_lines", "\n\na\n\n\r\nb\n")
  |> should.equal(["", "", "a", "", "", "b"])
}

pub fn only_newline_test() {
  lines_of("only_newline", "\n")
  |> should.equal([""])
}

pub fn line_spanning_chunk_boundary_test() {
  let long = string.repeat("x", 100)
  read_all("spanning", bit_array.from_string("ab\n" <> long <> "\ncd\n"), 16)
  |> should.equal(Ok(["ab", long, "cd"]))
}

pub fn multibyte_utf8_across_chunk_boundary_test() {
  // "é" is 2 bytes, "€" is 3 bytes, "😀" is 4 bytes, so a chunk size of 1, 2
  // or 3 cuts through these characters.
  lines_of("utf8", "é€😀\n<http://example.org/ø> \"日本語\" .\nÅ")
  |> should.equal(["é€😀", "<http://example.org/ø> \"日本語\" .", "Å"])
}

pub fn invalid_utf8_reports_line_number_test() {
  let bytes = <<"good\nalso good\n":utf8, 0xFF, 0xFE, "bad\nnever read\n":utf8>>
  read_all("invalid", bytes, 65_536)
  |> should.equal(Error(line_reader.InvalidUtf8(3)))
  read_all("invalid_small", bytes, 3)
  |> should.equal(Error(line_reader.InvalidUtf8(3)))
}

pub fn truncated_utf8_on_last_line_test() {
  // A multi-byte character cut off by the end of the file.
  read_all("truncated", <<"ok\n":utf8, 0xE2, 0x82>>, 1)
  |> should.equal(Error(line_reader.InvalidUtf8(2)))
}

pub fn line_number_test() {
  let file = path("line_number")
  let assert Ok(Nil) = simplifile.write(file, "a\nb\n")
  let assert Ok(stream) = file_stream.open_read(file)
  let reader = line_reader.new(stream)
  line_reader.line_number(reader) |> should.equal(0)
  let assert Ok(#("a", reader)) = line_reader.next(reader)
  line_reader.line_number(reader) |> should.equal(1)
  let assert Ok(#("b", reader)) = line_reader.next(reader)
  line_reader.line_number(reader) |> should.equal(2)
  line_reader.next(reader) |> should.equal(Error(line_reader.Eof))
  let assert Ok(Nil) = file_stream.close(stream)
  let assert Ok(Nil) = simplifile.delete(file)
}

pub fn fold_lines_test() {
  let file = path("fold")
  let assert Ok(Nil) = simplifile.write(file, "a\r\nb\nc")
  let assert Ok(stream) = file_stream.open_read(file)
  let result =
    line_reader.fold_lines(stream, [], fn(acc, line, number) {
      Ok([#(number, line), ..acc])
    })
  let assert Ok(Nil) = file_stream.close(stream)
  let assert Ok(Nil) = simplifile.delete(file)
  result |> should.equal(Ok([#(3, "c"), #(2, "b"), #(1, "a")]))
}

pub fn fold_lines_stops_at_callback_error_test() {
  let file = path("fold_stop")
  let assert Ok(Nil) = simplifile.write(file, "1\n2\nstop\n4\n")
  let assert Ok(stream) = file_stream.open_read(file)
  let result =
    line_reader.fold_lines(stream, [], fn(acc, line, number) {
      case line {
        "stop" -> Error(number)
        _ -> Ok([line, ..acc])
      }
    })
  let assert Ok(Nil) = file_stream.close(stream)
  let assert Ok(Nil) = simplifile.delete(file)
  result |> should.equal(Error(line_reader.CallbackError(3)))
}

pub fn fold_lines_reports_invalid_utf8_test() {
  let file = path("fold_invalid")
  let assert Ok(Nil) =
    simplifile.write_bits(file, <<"a\n":utf8, 0xC3, "\n":utf8>>)
  let assert Ok(stream) = file_stream.open_read(file)
  let result = line_reader.fold_lines(stream, 0, fn(n, _, _) { Ok(n + 1) })
  let assert Ok(Nil) = file_stream.close(stream)
  let assert Ok(Nil) = simplifile.delete(file)
  result
  |> should.equal(Error(line_reader.LineFailure(line_reader.InvalidUtf8(2))))
}

pub fn large_file_test() {
  // About 5 MB of short N-Triples-like lines.
  let line_count = 100_000
  let line = "<http://example.org/s> <http://example.org/p> \"o\" ."
  let file = path("large")
  let content =
    list.repeat(line <> "\n", line_count)
    |> string.concat
  let assert Ok(Nil) = simplifile.write(file, content)
  let assert Ok(stream) = file_stream.open_read(file)
  let result =
    line_reader.fold_lines(stream, #(0, 0), fn(acc, text, number) {
      let #(count, bytes) = acc
      case text == line && number == count + 1 {
        True -> Ok(#(count + 1, bytes + string.byte_size(text)))
        False -> Error(number)
      }
    })
  let assert Ok(Nil) = file_stream.close(stream)
  let assert Ok(Nil) = simplifile.delete(file)
  result
  |> should.equal(Ok(#(line_count, line_count * string.byte_size(line))))
}

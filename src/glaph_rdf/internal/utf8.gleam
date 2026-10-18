//// UTF-8 decoding that behaves the same on Erlang and JavaScript.
////
//// `bit_array.to_string` on JavaScript uses a `TextDecoder` that silently
//// drops a leading byte order mark (U+FEFF) on every call, while the Erlang
//// implementation keeps it. Text files read through `simplifile.read` inherit
//// that difference. This module decodes without ever dropping U+FEFF, and
//// leaves it to the caller to strip a byte order mark where one is allowed:
//// only at the very start of a file.

import gleam/bit_array
import simplifile

/// Decodes UTF-8 bytes, keeping any U+FEFF characters, including a leading
/// one. Returns `Error(Nil)` for invalid UTF-8.
///
/// ## Examples
///
/// ```gleam
/// utf8.decode(<<0xEF, 0xBB, 0xBF, "a":utf8>>)
/// // -> Ok("\u{FEFF}a")
/// ```
@external(javascript, "./utf8_ffi.mjs", "decode")
pub fn decode(bytes: BitArray) -> Result(String, Nil) {
  bit_array.to_string(bytes)
}

/// Removes one leading byte order mark (U+FEFF), if present.
///
/// ## Examples
///
/// ```gleam
/// utf8.strip_bom("\u{FEFF}<a> <b> <c> .")
/// // -> "<a> <b> <c> ."
/// ```
pub fn strip_bom(text: String) -> String {
  case text {
    "\u{FEFF}" <> rest -> rest
    _ -> text
  }
}

/// Reads a UTF-8 text file, keeping every U+FEFF (including a leading byte
/// order mark) so the result is the same on both targets. The string parsers
/// strip one leading byte order mark themselves, so `parse_file` and `parse`
/// agree. Invalid UTF-8 is reported as `simplifile.NotUtf8`.
///
/// ## Examples
///
/// ```gleam
/// // data.nt starts with the bytes EF BB BF
/// utf8.read_file("data.nt")
/// // -> Ok("\u{FEFF}<a> <b> <c> .\n")
/// ```
pub fn read_file(path: String) -> Result(String, simplifile.FileError) {
  case simplifile.read_bits(path) {
    Ok(bytes) ->
      case decode(bytes) {
        Ok(text) -> Ok(text)
        Error(Nil) -> Error(simplifile.NotUtf8)
      }
    Error(error) -> Error(error)
  }
}

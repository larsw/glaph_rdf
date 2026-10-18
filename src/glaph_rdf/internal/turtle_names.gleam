//// Prefixed names (`PNAME_NS` / `PNAME_LN`) as defined by the Turtle 1.1 and
//// 1.2 grammars, shared by the Turtle and TriG writers and the Turtle lexer.
////
//// ```text
//// PN_PREFIX    ::= PN_CHARS_BASE ((PN_CHARS | '.')* PN_CHARS)?
//// PN_LOCAL     ::= (PN_CHARS_U | ':' | [0-9] | PLX)
////                  ((PN_CHARS | '.' | ':' | PLX)* (PN_CHARS | ':' | PLX))?
//// PLX          ::= PERCENT | PN_LOCAL_ESC
//// PN_LOCAL_ESC ::= '\' ('_' | '~' | '.' | '-' | '!' | '$' | '&' | "'" | '('
////                  | ')' | '*' | '+' | ',' | ';' | '=' | '/' | '?' | '#'
////                  | '@' | '%')
//// ```
////
//// Everything here works on Unicode codepoints, never on grapheme clusters,
//// so that a namespace boundary that falls inside a cluster (for example
//// before a combining accent) behaves the same on Erlang and JavaScript.

import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string

/// Compacts an IRI to a prefixed name using the longest matching namespace
/// whose remainder can be written as a valid `PN_LOCAL`. Prefixes whose label
/// is not a valid `PN_PREFIX`, and empty namespaces, are ignored. Returns
/// `None` when no prefix applies, so the caller writes the full `<IRI>`.
///
/// Characters that `PN_LOCAL` only allows escaped are written with a
/// backslash (`PN_LOCAL_ESC`), and valid `%XX` sequences are kept as they
/// are. When two labels share the longest namespace, the smallest label wins
/// so the output does not depend on dictionary order.
///
/// ## Examples
///
/// ```gleam
/// let prefixes = dict.from_list([#("ex", "http://ex.org/")])
/// turtle_names.compact_iri("http://ex.org/a/b", prefixes)
/// // -> Some("ex:a\\/b")
/// turtle_names.compact_iri("http://ex.org/", prefixes)
/// // -> Some("ex:")
/// turtle_names.compact_iri("http://other.org/x", prefixes)
/// // -> None
/// ```
pub fn compact_iri(
  iri: String,
  prefixes: dict.Dict(String, String),
) -> Option(String) {
  dict.to_list(prefixes)
  |> list.fold(None, fn(best, entry) {
    let #(name, namespace) = entry
    case
      namespace != ""
      && string.starts_with(iri, namespace)
      && is_valid_prefix(name)
    {
      False -> best
      True -> {
        // `string.starts_with` compares bytes (Erlang) or UTF-16 units
        // (JavaScript), both of which only match on whole codepoints, so
        // dropping the namespace's codepoints leaves exactly the remainder.
        let namespace_length = list.length(string.to_utf_codepoints(namespace))
        let local =
          string.to_utf_codepoints(iri)
          |> list.drop(namespace_length)
        case escape_codepoints(local, True, []) {
          None -> best
          Some(escaped) -> {
            let better = case best {
              None -> True
              Some(#(best_name, _, best_length)) ->
                namespace_length > best_length
                || namespace_length == best_length
                && compare_labels(name, best_name) == order.Lt
            }
            case better {
              True -> Some(#(name, name <> ":" <> escaped, namespace_length))
              False -> best
            }
          }
        }
      }
    }
  })
  |> option.map(fn(best) { best.1 })
}

/// The prefix declarations to write, in a fixed order: only labels that are
/// valid `PN_PREFIX`es (others could not be read back), sorted with
/// `compare_labels`. Dictionary iteration order differs between Erlang and
/// JavaScript, so this keeps the `@prefix` lines byte-identical on both.
///
/// ## Examples
///
/// ```gleam
/// turtle_names.sorted_prefixes(
///   dict.from_list([#("b", "http://b/"), #("1x", "http://x/"), #("a", "http://a/")]),
/// )
/// // -> [#("a", "http://a/"), #("b", "http://b/")]
/// ```
pub fn sorted_prefixes(
  prefixes: dict.Dict(String, String),
) -> List(#(String, String)) {
  dict.to_list(prefixes)
  |> list.filter(fn(entry) { is_valid_prefix(entry.0) })
  |> list.sort(fn(a, b) { compare_labels(a.0, b.0) })
}

/// Orders two labels by Unicode codepoint. `string.compare` orders by UTF-8
/// bytes on Erlang but by UTF-16 code units on JavaScript, which disagree
/// for characters above U+FFFF, so it cannot be used for output order.
///
/// ## Examples
///
/// ```gleam
/// turtle_names.compare_labels("a", "b")
/// // -> order.Lt
/// turtle_names.compare_labels("\u{FF41}", "\u{1F600}")
/// // -> order.Lt
/// ```
pub fn compare_labels(a: String, b: String) -> order.Order {
  compare_codepoints(string.to_utf_codepoints(a), string.to_utf_codepoints(b))
}

fn compare_codepoints(
  a: List(UtfCodepoint),
  b: List(UtfCodepoint),
) -> order.Order {
  case a, b {
    [], [] -> order.Eq
    [], _ -> order.Lt
    _, [] -> order.Gt
    [x, ..a], [y, ..b] ->
      case
        int.compare(
          string.utf_codepoint_to_int(x),
          string.utf_codepoint_to_int(y),
        )
      {
        order.Eq -> compare_codepoints(a, b)
        other -> other
      }
  }
}

/// Writes a local name as a valid `PN_LOCAL`, escaping the characters that
/// the grammar only allows after a backslash, or returns `None` when that is
/// impossible (for example a space, or a combining mark at the start). The
/// empty local name is valid.
///
/// ## Examples
///
/// ```gleam
/// turtle_names.escape_local("-x.")
/// // -> Some("\\-x\\.")
/// turtle_names.escape_local("a%41b")
/// // -> Some("a%41b")
/// turtle_names.escape_local("a b")
/// // -> None
/// ```
pub fn escape_local(local: String) -> Option(String) {
  escape_codepoints(string.to_utf_codepoints(local), True, [])
}

fn escape_codepoints(
  codepoints: List(UtfCodepoint),
  first: Bool,
  acc: List(String),
) -> Option(String) {
  case codepoints {
    [] -> Some(string.concat(list.reverse(acc)))
    [codepoint, ..rest] -> {
      let code = string.utf_codepoint_to_int(codepoint)
      let char = string.from_utf_codepoints([codepoint])
      case code {
        // '%': keep a valid %XX sequence, escape a bare percent sign.
        0x25 ->
          case rest {
            [high, low, ..tail] ->
              case
                is_hex(string.utf_codepoint_to_int(high))
                && is_hex(string.utf_codepoint_to_int(low))
              {
                True ->
                  escape_codepoints(tail, False, [
                    string.from_utf_codepoints([codepoint, high, low]),
                    ..acc
                  ])
                False -> escape_codepoints(rest, False, ["\\%", ..acc])
              }
            _ -> escape_codepoints(rest, False, ["\\%", ..acc])
          }
        // '.' may not start or end a local name unescaped.
        0x2E ->
          case first || rest == [] {
            True -> escape_codepoints(rest, False, ["\\.", ..acc])
            False -> escape_codepoints(rest, False, [".", ..acc])
          }
        // '-' is in PN_CHARS but not PN_CHARS_U, so it cannot start one.
        0x2D ->
          case first {
            True -> escape_codepoints(rest, False, ["\\-", ..acc])
            False -> escape_codepoints(rest, False, ["-", ..acc])
          }
        // ':' and '_' are allowed unescaped anywhere.
        0x3A | 0x5F -> escape_codepoints(rest, False, [char, ..acc])
        _ ->
          case is_local_escape_code(code) {
            True -> escape_codepoints(rest, False, ["\\" <> char, ..acc])
            False -> {
              let allowed = case first {
                True -> is_pn_chars_u(code) || is_digit(code)
                False -> is_pn_chars(code)
              }
              case allowed {
                True -> escape_codepoints(rest, False, [char, ..acc])
                False -> None
              }
            }
          }
      }
    }
  }
}

/// Whether a prefix label can be written in a `@prefix` directive and in a
/// prefixed name: the empty label or a valid `PN_PREFIX`.
///
/// ## Examples
///
/// ```gleam
/// turtle_names.is_valid_prefix("ex")
/// // -> True
/// turtle_names.is_valid_prefix("")
/// // -> True
/// turtle_names.is_valid_prefix("1ex")
/// // -> False
/// turtle_names.is_valid_prefix("ex.")
/// // -> False
/// ```
pub fn is_valid_prefix(label: String) -> Bool {
  case
    string.to_utf_codepoints(label) |> list.map(string.utf_codepoint_to_int)
  {
    [] -> True
    [first, ..rest] ->
      is_pn_chars_base(first)
      && list.all(rest, fn(code) { is_pn_chars(code) || code == 0x2E })
      && list.last(rest) != Ok(0x2E)
  }
}

/// Whether a single-codepoint string may start a `PN_PREFIX`
/// (`PN_CHARS_BASE`).
///
/// ## Examples
///
/// ```gleam
/// turtle_names.is_prefix_start_char("é")
/// // -> True
/// turtle_names.is_prefix_start_char("_")
/// // -> False
/// ```
pub fn is_prefix_start_char(char: String) -> Bool {
  is_pn_chars_base(char_code(char))
}

/// Whether a single-codepoint string may appear after the first character of
/// a `PN_PREFIX` (`PN_CHARS` or '.'; a trailing '.' is the caller's concern).
///
/// ## Examples
///
/// ```gleam
/// turtle_names.is_prefix_char("-")
/// // -> True
/// turtle_names.is_prefix_char(":")
/// // -> False
/// ```
pub fn is_prefix_char(char: String) -> Bool {
  let code = char_code(char)
  is_pn_chars(code) || code == 0x2E
}

/// Whether a single-codepoint string may start a `PN_LOCAL` without an
/// escape (`PN_CHARS_U`, ':' or a digit; `PLX` is the caller's concern).
///
/// ## Examples
///
/// ```gleam
/// turtle_names.is_local_start_char("1")
/// // -> True
/// turtle_names.is_local_start_char("-")
/// // -> False
/// ```
pub fn is_local_start_char(char: String) -> Bool {
  let code = char_code(char)
  is_pn_chars_u(code) || code == 0x3A || is_digit(code)
}

/// Whether a single-codepoint string may appear unescaped after the first
/// character of a `PN_LOCAL` (`PN_CHARS` or ':'; '.' and `PLX` are the
/// caller's concern).
///
/// ## Examples
///
/// ```gleam
/// turtle_names.is_local_char("-")
/// // -> True
/// turtle_names.is_local_char("/")
/// // -> False
/// ```
pub fn is_local_char(char: String) -> Bool {
  let code = char_code(char)
  is_pn_chars(code) || code == 0x3A
}

/// Whether a single-codepoint string may follow a backslash in a
/// `PN_LOCAL_ESC`.
///
/// ## Examples
///
/// ```gleam
/// turtle_names.is_local_escape_char("/")
/// // -> True
/// turtle_names.is_local_escape_char("a")
/// // -> False
/// ```
pub fn is_local_escape_char(char: String) -> Bool {
  let code = char_code(char)
  is_local_escape_code(code) || code == 0x2E || code == 0x2D || code == 0x5F
}

// The PN_LOCAL_ESC characters other than '_', '.' and '-', which are also
// allowed unescaped in some positions and so are handled separately.
fn is_local_escape_code(code: Int) -> Bool {
  case code {
    0x7E | 0x21 | 0x24 | 0x26 | 0x27 | 0x28 | 0x29 | 0x2A | 0x2B | 0x2C -> True
    0x3B | 0x3D | 0x2F | 0x3F | 0x23 | 0x40 | 0x25 -> True
    _ -> False
  }
}

fn char_code(char: String) -> Int {
  case string.to_utf_codepoints(char) {
    [codepoint] -> string.utf_codepoint_to_int(codepoint)
    _ -> -1
  }
}

fn is_digit(code: Int) -> Bool {
  code >= 0x30 && code <= 0x39
}

fn is_hex(code: Int) -> Bool {
  is_digit(code)
  || { code >= 0x41 && code <= 0x46 }
  || { code >= 0x61 && code <= 0x66 }
}

fn is_pn_chars_base(code: Int) -> Bool {
  { code >= 0x41 && code <= 0x5A }
  || { code >= 0x61 && code <= 0x7A }
  || { code >= 0xC0 && code <= 0xD6 }
  || { code >= 0xD8 && code <= 0xF6 }
  || { code >= 0xF8 && code <= 0x2FF }
  || { code >= 0x370 && code <= 0x37D }
  || { code >= 0x37F && code <= 0x1FFF }
  || { code >= 0x200C && code <= 0x200D }
  || { code >= 0x2070 && code <= 0x218F }
  || { code >= 0x2C00 && code <= 0x2FEF }
  || { code >= 0x3001 && code <= 0xD7FF }
  || { code >= 0xF900 && code <= 0xFDCF }
  || { code >= 0xFDF0 && code <= 0xFFFD }
  || { code >= 0x10000 && code <= 0xEFFFF }
}

fn is_pn_chars_u(code: Int) -> Bool {
  is_pn_chars_base(code) || code == 0x5F
}

fn is_pn_chars(code: Int) -> Bool {
  is_pn_chars_u(code)
  || code == 0x2D
  || is_digit(code)
  || code == 0xB7
  || { code >= 0x300 && code <= 0x36F }
  || { code >= 0x203F && code <= 0x2040 }
}

// Numeric and boolean literals -----------------------------------------------
//
// ```text
// INTEGER   ::= [+-]? [0-9]+
// DECIMAL   ::= [+-]? [0-9]* '.' [0-9]+
// DOUBLE    ::= [+-]? ([0-9]+ '.' [0-9]* EXPONENT | '.'? [0-9]+ EXPONENT)
// EXPONENT  ::= [eE] [+-]? [0-9]+
// BooleanLiteral ::= 'true' | 'false'
// ```

/// The kind of a bare Turtle number, which fixes its datatype.
pub type NumberKind {
  IntegerNumber
  DecimalNumber
  DoubleNumber
}

/// The longest Turtle number at the start of `chars` (one character per
/// element): its kind and how many characters it takes. A '.' that is not
/// followed by a digit or an exponent is not part of the number, so `1.`
/// is the integer `1` followed by the statement terminator.
///
/// ## Examples
///
/// ```gleam
/// turtle_names.scan_number(["1", ".", "5", " "])
/// // -> Ok(#(DecimalNumber, 3))
/// turtle_names.scan_number(["1", ".", " "])
/// // -> Ok(#(IntegerNumber, 1))
/// ```
pub fn scan_number(chars: List(String)) -> Result(#(NumberKind, Int), Nil) {
  let #(sign, rest) = case chars {
    ["+", ..rest] | ["-", ..rest] -> #(1, rest)
    _ -> #(0, chars)
  }
  let #(whole, rest) = count_digits(rest, 0)
  let integer = case whole > 0 {
    True -> Ok(#(IntegerNumber, sign + whole))
    False -> Error(Nil)
  }
  case rest {
    [".", ..after_dot] -> {
      let #(fraction, rest) = count_digits(after_dot, 0)
      case scan_exponent(rest) {
        Ok(exponent) if whole + fraction > 0 ->
          Ok(#(DoubleNumber, sign + whole + 1 + fraction + exponent))
        _ ->
          case fraction > 0 {
            True -> Ok(#(DecimalNumber, sign + whole + 1 + fraction))
            False -> integer
          }
      }
    }
    _ ->
      case scan_exponent(rest) {
        Ok(exponent) if whole > 0 -> Ok(#(DoubleNumber, sign + whole + exponent))
        _ -> integer
      }
  }
}

fn count_digits(chars: List(String), count: Int) -> #(Int, List(String)) {
  case chars {
    [char, ..rest] ->
      case is_digit(char_code(char)) {
        True -> count_digits(rest, count + 1)
        False -> #(count, chars)
      }
    [] -> #(count, chars)
  }
}

fn scan_exponent(chars: List(String)) -> Result(Int, Nil) {
  let after_e = case chars {
    ["e", ..rest] | ["E", ..rest] -> Ok(rest)
    _ -> Error(Nil)
  }
  case after_e {
    Error(Nil) -> Error(Nil)
    Ok(rest) -> {
      let #(sign, rest) = case rest {
        ["+", ..rest] | ["-", ..rest] -> #(1, rest)
        _ -> #(0, rest)
      }
      case count_digits(rest, 0) {
        #(0, _) -> Error(Nil)
        #(digits, _) -> Ok(1 + sign + digits)
      }
    }
  }
}

/// Whether a literal with this lexical form and datatype IRI can be written
/// as a bare Turtle number or boolean that reads back as exactly the same
/// literal. Anything else (an ill-typed form such as `"abc"^^xsd:integer`,
/// or a form whose bare spelling has another datatype, such as
/// `"1"^^xsd:double`) has to be written quoted with `^^`.
///
/// ## Examples
///
/// ```gleam
/// turtle_names.is_bare_literal("-1.5", "http://www.w3.org/2001/XMLSchema#decimal")
/// // -> True
/// turtle_names.is_bare_literal("1", "http://www.w3.org/2001/XMLSchema#double")
/// // -> False
/// ```
pub fn is_bare_literal(value: String, datatype: String) -> Bool {
  let xsd = "http://www.w3.org/2001/XMLSchema#"
  let expected = case datatype == xsd <> "integer" {
    True -> Ok(IntegerNumber)
    False ->
      case datatype == xsd <> "decimal" {
        True -> Ok(DecimalNumber)
        False ->
          case datatype == xsd <> "double" {
            True -> Ok(DoubleNumber)
            False -> Error(Nil)
          }
      }
  }
  case expected {
    Ok(kind) -> {
      let chars = string.to_graphemes(value)
      scan_number(chars) == Ok(#(kind, list.length(chars)))
    }
    Error(Nil) ->
      datatype == xsd <> "boolean" && { value == "true" || value == "false" }
  }
}

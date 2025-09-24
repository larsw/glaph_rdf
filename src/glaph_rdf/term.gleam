import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri

const ascii_letters = [
  "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
  "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
]

const irregular_language_tags = [
  "en-gb-oed",
  "i-ami",
  "i-bnn",
  "i-default",
  "i-enochian",
  "i-hak",
  "i-klingon",
  "i-lux",
  "i-mingo",
  "i-navajo",
  "i-pwn",
  "i-tao",
  "i-tay",
  "i-tsu",
  "sgn-be-fr",
  "sgn-be-nl",
  "sgn-ch-de",
]

const regular_language_tags = [
  "art-lojban",
  "cel-gaulish",
  "no-bok",
  "no-nyn",
  "zh-guoyu",
  "zh-hakka",
  "zh-min",
  "zh-min-nan",
  "zh-xiang",
]

fn grandfathered_language_tags() -> List(String) {
  list.flatten([irregular_language_tags, regular_language_tags])
}

pub type TermError {
  InvalidIri(String)
  InvalidBlankNodeIdentifier(String)
  InvalidLanguageTag(String)
  InvalidSubjectTerm
  InvalidGraphNameTerm
}

pub type NamedNode {
  NamedNode(value: String)
}

pub type BlankNode {
  BlankNode(identifier: String)
}

pub type LanguageTag {
  LanguageTag(value: String)
}

pub type Literal {
  SimpleLiteral(value: String)
  LanguageTaggedLiteral(value: String, tag: LanguageTag)
  TypedLiteral(value: String, datatype: NamedNode)
}

pub type Term {
  NamedTerm(node: NamedNode)
  BlankTerm(node: BlankNode)
  LiteralTerm(literal: Literal)
}

pub type Subject {
  SubjectNamed(node: NamedNode)
  SubjectBlank(node: BlankNode)
}

pub type Predicate = NamedNode

pub type Object {
  ObjectNamed(node: NamedNode)
  ObjectBlank(node: BlankNode)
  ObjectLiteral(literal: Literal)
}

pub type GraphName {
  DefaultGraph
  NamedGraph(node: NamedNode)
  BlankGraph(node: BlankNode)
}

pub fn named_node(value: String) -> Result(NamedNode, TermError) {
  case validate_iri(value) {
    True -> Ok(NamedNode(value))
    False -> Error(InvalidIri(value))
  }
}

pub fn unsafe_named_node(value: String) -> NamedNode {
  NamedNode(value)
}

pub fn blank_node(identifier: String) -> Result(BlankNode, TermError) {
  case is_valid_blank_node_identifier(identifier) {
    True -> Ok(BlankNode(identifier))
    False -> Error(InvalidBlankNodeIdentifier(identifier))
  }
}

pub fn unsafe_blank_node(identifier: String) -> BlankNode {
  BlankNode(identifier)
}

pub fn language_tag(value: String) -> Result(LanguageTag, TermError) {
  let lower = string.lowercase(value)
  case canonical_language_tag(lower) {
    Ok(canonical) -> Ok(LanguageTag(canonical))
    Error(_) -> Error(InvalidLanguageTag(value))
  }
}

pub fn simple_literal(value: String) -> Literal {
  SimpleLiteral(value)
}

pub fn language_literal(value: String, tag: LanguageTag) -> Literal {
  LanguageTaggedLiteral(value, tag)
}

pub fn typed_literal(value: String, datatype: NamedNode) -> Literal {
  TypedLiteral(value, datatype)
}

pub fn term_from_subject(subject: Subject) -> Term {
  case subject {
    SubjectNamed(node) -> NamedTerm(node)
    SubjectBlank(node) -> BlankTerm(node)
  }
}

pub fn term_from_object(object: Object) -> Term {
  case object {
    ObjectNamed(node) -> NamedTerm(node)
    ObjectBlank(node) -> BlankTerm(node)
    ObjectLiteral(literal) -> LiteralTerm(literal)
  }
}

pub fn subject_from_term(term: Term) -> Result(Subject, TermError) {
  case term {
    NamedTerm(node) -> Ok(SubjectNamed(node))
    BlankTerm(node) -> Ok(SubjectBlank(node))
    LiteralTerm(_) -> Error(InvalidSubjectTerm)
  }
}

pub fn object_from_term(term: Term) -> Object {
  case term {
    NamedTerm(node) -> ObjectNamed(node)
    BlankTerm(node) -> ObjectBlank(node)
    LiteralTerm(literal) -> ObjectLiteral(literal)
  }
}

pub fn graph_name_from_term(term: Term) -> Result(GraphName, TermError) {
  case term {
    NamedTerm(node) -> Ok(NamedGraph(node))
    BlankTerm(node) -> Ok(BlankGraph(node))
    LiteralTerm(_) -> Error(InvalidGraphNameTerm)
  }
}

pub fn iri_to_uri(value: String) -> Result(uri.Uri, TermError) {
  parse_encoded_iri(value)
}

pub fn uri_to_iri(uri_value: uri.Uri) -> Result(String, TermError) {
  uri.to_string(uri_value)
  |> decode_iri
}

pub fn named_node_to_uri(node: NamedNode) -> Result(uri.Uri, TermError) {
  let NamedNode(value) = node
  iri_to_uri(value)
}

pub fn named_node_from_uri(uri_value: uri.Uri) -> Result(NamedNode, TermError) {
  uri_to_iri(uri_value)
  |> result.try(named_node)
}

pub fn decode_iri(value: String) -> Result(String, TermError) {
  decode_iri_loop(string.to_graphemes(value), [], value)
}

fn decode_iri_loop(
  graphemes: List(String),
  acc: List(String),
  original: String,
) -> Result(String, TermError) {
  case graphemes {
    [] -> Ok(string.concat(list.reverse(acc)))
    ["%", .._] ->
      case decode_percent_sequence(graphemes) {
        Ok(#(segment, rest)) ->
          decode_iri_loop(rest, [segment, ..acc], original)

        Error(_) -> Error(InvalidIri(original))
      }
    [head, ..rest] -> decode_iri_loop(rest, [head, ..acc], original)
  }
}

fn decode_percent_sequence(
  graphemes: List(String),
) -> Result(#(String, List(String)), Nil) {
  take_percent_encoded(graphemes, [])
  |> result.try(fn(result) {
    let #(encoded, rest) = result
    case uri.percent_decode(encoded) {
      Ok(decoded) -> {
        let cp_ints =
          string.to_utf_codepoints(decoded)
          |> list.map(string.utf_codepoint_to_int)
        case list.all(cp_ints, fn(cp) { cp > 0x7F }) {
          True -> Ok(#(decoded, rest))
          False -> Ok(#(encoded, rest))
        }
      }
      Error(_) -> Error(Nil)
    }
  })
}

fn take_percent_encoded(
  graphemes: List(String),
  acc: List(String),
) -> Result(#(String, List(String)), Nil) {
  case graphemes {
    ["%", x, y, ..rest] ->
      case is_hex_digit(x) && is_hex_digit(y) {
        True -> take_percent_encoded(rest, [y, x, "%", ..acc])
        False -> Error(Nil)
      }
    _ ->
      case acc {
        [] -> Error(Nil)
        _ -> {
          let encoded = string.concat(list.reverse(acc))
          Ok(#(encoded, graphemes))
        }
      }
  }
}

fn validate_iri(value: String) -> Bool {
  case string.split_once(value, ":") {
    Ok(#(scheme, _rest)) ->
      is_valid_scheme(scheme)
        && result.is_ok(parse_encoded_iri(value))

    Error(_) -> False
  }
}

fn is_valid_scheme(scheme: String) -> Bool {
  case string.to_graphemes(scheme) {
    [] -> False
    [first, ..rest] ->
      is_ascii_letter(first)
        && list.all(rest, fn(char) {
          is_ascii_letter(char) || is_digit(char) || char == "+" || char == "-" || char == "."
        })
  }
}

fn parse_encoded_iri(value: String) -> Result(uri.Uri, TermError) {
  case uri.parse(percent_encode_iri(value)) {
    Ok(parsed) -> Ok(parsed)
    Error(_) -> Error(InvalidIri(value))
  }
}

fn percent_encode_iri(value: String) -> String {
  value
  |> string.to_utf_codepoints
  |> list.map(encode_iri_codepoint)
  |> string.concat
}

fn encode_iri_codepoint(codepoint) -> String {
  let cp = string.utf_codepoint_to_int(codepoint)
  case cp <= 0x7F {
    True -> string.from_utf_codepoints([codepoint])
    False ->
      encode_codepoint_bytes(cp)
      |> list.map(percent_encode_byte)
      |> string.concat
  }
}

fn encode_codepoint_bytes(codepoint: Int) -> List(Int) {
  case codepoint {
    cp if cp <= 0x7F -> [cp]
    cp if cp <= 0x7FF -> [
      0xC0 + int.bitwise_shift_right(cp, 6),
      0x80 + int.bitwise_and(cp, 0x3F),
    ]
    cp if cp <= 0xFFFF -> [
      0xE0 + int.bitwise_shift_right(cp, 12),
      0x80 + int.bitwise_and(int.bitwise_shift_right(cp, 6), 0x3F),
      0x80 + int.bitwise_and(cp, 0x3F),
    ]
    cp if cp <= 0x10FFFF -> [
      0xF0 + int.bitwise_shift_right(cp, 18),
      0x80 + int.bitwise_and(int.bitwise_shift_right(cp, 12), 0x3F),
      0x80 + int.bitwise_and(int.bitwise_shift_right(cp, 6), 0x3F),
      0x80 + int.bitwise_and(cp, 0x3F),
    ]
    _ -> []
  }
}

fn percent_encode_byte(byte: Int) -> String {
  let upper = string.uppercase(int.to_base16(byte))
  case string.length(upper) {
    1 -> "%0" <> upper
    _ -> "%" <> upper
  }
}

fn is_valid_blank_node_identifier(identifier: String) -> Bool {
  case string.to_graphemes(identifier) {
    [] -> False
    [first, ..rest] ->
      is_valid_blank_head(first)
        && is_valid_blank_body(first)
        && list.all(rest, fn(char) { is_valid_blank_body(char) })
  }
}

fn is_valid_blank_head(char: String) -> Bool {
  is_ascii_letter(char) || char == "_"
}

fn is_valid_blank_body(char: String) -> Bool {
  is_ascii_letter(char) || is_digit(char) || char == "_" || char == "."
}

fn is_ascii_letter(char: String) -> Bool {
  case string.to_graphemes(string.lowercase(char)) {
    [single] -> list.any(ascii_letters, fn(letter) { letter == single })
    _ -> False
  }
}

fn is_digit(char: String) -> Bool {
  case char {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}

fn is_hex_digit(char: String) -> Bool {
  let lower = string.lowercase(char)
  case lower {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    "a" | "b" | "c" | "d" | "e" | "f" -> True
    _ -> False
  }
}

fn is_grandfathered_tag(tag: String) -> Bool {
  list.any(grandfathered_language_tags(), fn(existing) { existing == tag })
}

fn canonical_language_tag(value: String) -> Result(String, Nil) {
  case value {
    "" -> Error(Nil)
    _ ->
      case is_grandfathered_tag(value) {
        True -> Ok(value)
        False ->
          case string.split(value, "-") {
            ["x", ..rest] -> canonical_privateuse(rest)
            subtags -> build_canonical_langtag(subtags)
          }
      }
  }
}

fn canonical_privateuse(subtags: List(String)) -> Result(String, Nil) {
  case subtags {
    [] -> Error(Nil)
    tags -> {
      case list.all(tags, is_privateuse_subtag) {
        True -> {
          let lowered = list.map(tags, string.lowercase)
          Ok("x-" <> string.join(lowered, "-"))
        }
        False -> Error(Nil)
      }
    }
  }
}

fn build_canonical_langtag(subtags: List(String)) -> Result(String, Nil) {
  case subtags {
    [language, ..rest] -> {
      case validate_language_subtag(language) {
        False -> Error(Nil)
        True -> {
          let lang_len = string.length(language)
          let canonical_language = string.lowercase(language)
          let #(extlangs, after_extlangs) =
            case lang_len >= 2 && lang_len <= 3 {
              True -> extract_extlangs(rest)
              False -> #([], rest)
            }
          let #(script, after_script) = extract_script(after_extlangs)
          let #(region, after_region) = extract_region(after_script)
          let #(variants, after_variants) = extract_variants(after_region)
          case extract_extensions(after_variants) {
            Ok(#(extensions, after_extensions)) ->
              case extract_privateuse(after_extensions) {
                Ok(#(privateuse, remainder)) ->
                  case remainder {
                    [] -> Ok(
                      assemble_canonical_language_tag(
                        canonical_language,
                        extlangs,
                        script,
                        region,
                        variants,
                        extensions,
                        privateuse,
                      ),
                    )
                    _ -> Error(Nil)
                  }
                Error(_) -> Error(Nil)
              }
            Error(_) -> Error(Nil)
          }
        }
      }
    }
    [] -> Error(Nil)
  }
}

fn assemble_canonical_language_tag(
  language: String,
  extlangs: List(String),
  script: Option(String),
  region: Option(String),
  variants: List(String),
  extensions: List(List(String)),
  privateuse: Option(List(String)),
) -> String {
  let base = list.append([language], list.map(extlangs, string.lowercase))
  let base =
    case script {
      Some(value) -> list.append(base, [canonical_script(value)])
      None -> base
    }
  let base =
    case region {
      Some(value) -> list.append(base, [canonical_region(value)])
      None -> base
    }
  let base = list.append(base, list.map(variants, string.lowercase))
  let extension_parts =
    extensions
    |> list.map(canonical_extension)
    |> list.flatten
  let base = list.append(base, extension_parts)
  let base =
    case privateuse {
      Some(values) -> {
        let private_parts =
          list.append(["x"], list.map(values, string.lowercase))
        list.append(base, private_parts)
      }
      None -> base
    }
  string.join(base, "-")
}

fn validate_language_subtag(language: String) -> Bool {
  let len = string.length(language)
  case len {
    len if len >= 2 && len <= 3 -> is_alpha_string(language)
    4 -> is_alpha_string(language)
    len if len >= 5 && len <= 8 -> is_alpha_string(language)
    _ -> False
  }
}

fn extract_extlangs(subtags: List(String)) -> #(List(String), List(String)) {
  extract_extlangs_loop(subtags, [])
}

fn extract_extlangs_loop(
  subtags: List(String),
  acc: List(String),
) -> #(List(String), List(String)) {
  case subtags {
    [candidate, ..rest] ->
      case list.length(acc) < 3
        && string.length(candidate) == 3
        && is_alpha_string(candidate) {
        True -> extract_extlangs_loop(rest, [candidate, ..acc])
        False -> #(list.reverse(acc), subtags)
      }
    [] -> #(list.reverse(acc), [])
  }
}

fn extract_script(subtags: List(String)) -> #(Option(String), List(String)) {
  case subtags {
    [script, ..rest] ->
      case string.length(script) == 4 && is_alpha_string(script) {
        True -> #(Some(script), rest)
        False -> #(None, subtags)
      }
    [] -> #(None, [])
  }
}

fn extract_region(subtags: List(String)) -> #(Option(String), List(String)) {
  case subtags {
    [region, ..rest] ->
      case string.length(region) {
        2 ->
          case is_alpha_string(region) {
            True -> #(Some(region), rest)
            False -> #(None, subtags)
          }
        3 ->
          case is_digit_string(region) {
            True -> #(Some(region), rest)
            False -> #(None, subtags)
          }
        _ -> #(None, subtags)
      }
    [] -> #(None, [])
  }
}

fn extract_variants(subtags: List(String)) -> #(List(String), List(String)) {
  extract_variants_loop(subtags, [])
}

fn extract_variants_loop(
  subtags: List(String),
  acc: List(String),
) -> #(List(String), List(String)) {
  case subtags {
    [variant, ..rest] ->
      case is_variant_subtag(variant) {
        True -> extract_variants_loop(rest, [variant, ..acc])
        False -> #(list.reverse(acc), subtags)
      }
    [] -> #(list.reverse(acc), [])
  }
}

fn extract_extensions(
  subtags: List(String),
) -> Result(#(List(List(String)), List(String)), Nil) {
  extract_extensions_loop(subtags, [])
}

fn extract_extensions_loop(
  subtags: List(String),
  acc: List(List(String)),
) -> Result(#(List(List(String)), List(String)), Nil) {
  case subtags {
    [singleton, ..rest] ->
      case is_extension_singleton(singleton) {
        True ->
          case extract_extension_subtags(rest, []) {
            Ok(#(subtags_list, remainder)) ->
              extract_extensions_loop(remainder, [[singleton, ..subtags_list], ..acc])
            Error(_) -> Error(Nil)
          }
        False -> Ok(#(list.reverse(acc), subtags))
      }
    [] -> Ok(#(list.reverse(acc), []))
  }
}

fn extract_extension_subtags(
  subtags: List(String),
  acc: List(String),
) -> Result(#(List(String), List(String)), Nil) {
  case subtags {
    [subtag, ..rest] ->
      case is_extension_subtag(subtag) {
        True -> extract_extension_subtags(rest, [subtag, ..acc])
        False ->
          case acc {
            [] -> Error(Nil)
            _ -> Ok(#(list.reverse(acc), subtags))
          }
      }
    [] ->
      case acc {
        [] -> Error(Nil)
        _ -> Ok(#(list.reverse(acc), []))
      }
  }
}

fn extract_privateuse(
  subtags: List(String),
) -> Result(#(Option(List(String)), List(String)), Nil) {
  case subtags {
    ["x", ..rest] ->
      case rest {
        [] -> Error(Nil)
        _ ->
          case list.all(rest, is_privateuse_subtag) {
            True -> Ok(#(Some(rest), []))
            False -> Error(Nil)
          }
      }
    _ -> Ok(#(None, subtags))
  }
}

fn canonical_script(script: String) -> String {
  case string.to_graphemes(script) {
    [first, ..rest] ->
      string.uppercase(first) <> string.concat(list.map(rest, string.lowercase))
    [] -> script
  }
}

fn canonical_region(region: String) -> String {
  case string.length(region) {
    2 -> string.uppercase(region)
    _ -> region
  }
}

fn canonical_extension(extension: List(String)) -> List(String) {
  case extension {
    [singleton, ..rest] ->
      [string.lowercase(singleton), ..list.map(rest, string.lowercase)]
    [] -> []
  }
}

fn is_alpha_string(value: String) -> Bool {
  string.to_graphemes(value)
  |> list.all(is_ascii_letter)
}

fn is_digit_string(value: String) -> Bool {
  string.to_graphemes(value)
  |> list.all(is_digit)
}

fn is_alphanum_string(value: String) -> Bool {
  string.to_graphemes(value)
  |> list.all(fn(char) { is_ascii_letter(char) || is_digit(char) })
}

fn is_variant_subtag(value: String) -> Bool {
  case string.length(value) {
    len if len >= 5 && len <= 8 -> is_alphanum_string(value)
    4 ->
      case string.to_graphemes(value) {
        [first, ..rest] ->
          is_digit(first) && list.all(rest, fn(char) { is_ascii_letter(char) || is_digit(char) })
        [] -> False
      }
    _ -> False
  }
}

fn is_extension_singleton(value: String) -> Bool {
  case string.to_graphemes(value) {
    [single] ->
      is_alphanum_string(single) && single != "x"
    _ -> False
  }
}

fn is_extension_subtag(value: String) -> Bool {
  let len = string.length(value)
  len >= 2 && len <= 8 && is_alphanum_string(value)
}

fn is_privateuse_subtag(value: String) -> Bool {
  let len = string.length(value)
  len >= 1 && len <= 8 && is_alphanum_string(value)
}

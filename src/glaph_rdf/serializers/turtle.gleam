//// Public API ////////////////////////////////////////////////////////////////
//// Tokenizer /////////////////////////////////////////////////////////////////
//// Parser ////////////////////////////////////////////////////////////////////
//// Serialization /////////////////////////////////////////////////////////////

import glaph_rdf/graph
import glaph_rdf/internal/rdf_syntax
import glaph_rdf/internal/turtle_names.{
  type NumberKind, DecimalNumber, DoubleNumber, IntegerNumber,
}
import glaph_rdf/internal/utf8
import glaph_rdf/statement
import glaph_rdf/term
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile

const rdf_type = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"

const xsd_integer = "http://www.w3.org/2001/XMLSchema#integer"

const xsd_decimal = "http://www.w3.org/2001/XMLSchema#decimal"

const xsd_double = "http://www.w3.org/2001/XMLSchema#double"

const xsd_boolean = "http://www.w3.org/2001/XMLSchema#boolean"

/// A complete Turtle document with base IRI, prefixes, and RDF graph content.
///
/// Represents a parsed or serializable Turtle document containing all the
/// components: optional base IRI for resolving relative references, namespace
/// prefixes for abbreviated IRIs, and the RDF graph containing the actual data.
/// Supports RDF 1.2 triple terms with `<<( s p o )>>` syntax.
///
/// ## Examples
/// ```gleam
/// TurtleDocument(
///   base: Some("http://example.org/"),
///   prefixes: dict.from_list([("ex", "http://example.org/"), ("foaf", "http://xmlns.com/foaf/0.1/")]),
///   graph: my_rdf_graph
/// )
/// ```
pub type TurtleDocument {
  TurtleDocument(
    base: Option(String),
    prefixes: dict.Dict(String, String),
    graph: graph.Graph,
  )
}

/// Error information from Turtle parsing operations.
///
/// Contains detailed error information including a descriptive message
/// and the character position where the error occurred in the input text.
/// This enables precise error reporting for debugging Turtle syntax issues.
///
/// ## Examples
/// ```gleam
/// TurtleError(
///   message: "Unexpected character '<' at position 42", 
///   position: 42
/// )
/// ```
pub type TurtleError {
  TurtleError(message: String, position: Int)
}

type TokenKind {
  PrefixDirective
  BaseDirective
  PrefixLabel(String)
  Dot
  Semicolon
  Comma
  HatHat
  LangTag(String)
  IriRef(String)
  Prefixed(String, String)
  BlankLabel(String)
  StringLiteral(String)
  NumberLiteral(NumberKind, String)
  BooleanLiteral(Bool)
  Word(String)
  /// `<<(`, the start of a triple term.
  TripleTermStart
  /// `)>>`, the end of a triple term.
  TripleTermEnd
  /// `{`, the start of a TriG graph block.
  GraphStart
  /// `}`, the end of a TriG graph block.
  GraphEnd
}

type Token {
  Token(kind: TokenKind, position: Int)
}

type LexerState {
  LexerState(chars: List(String), position: Int)
}

type ParserState {
  ParserState(tokens: List(Token))
}

/// Parse a Turtle document from text into a structured representation.
///
/// Parses base and prefix directives (anywhere between statements), triples
/// with predicate and object lists, IRIs, prefixed names, blank node labels,
/// all four string forms (`"..."`, `'...'`, `"""..."""`, `'''...'''`),
/// numbers, booleans, language tags, RDF 1.2 directional language tags
/// (`"x"@en--ltr`), datatypes and RDF 1.2 triple terms (`<<( s p o )>>`).
/// Collections, `[ ... ]` blank nodes, reified triples (`<< ... >>`) and
/// annotations (`{| ... |}`) are not supported yet and give an error.
/// Returns detailed error information on parse failures.
///
/// ## Examples
/// ```gleam
/// let turtle_text = "@prefix ex: <http://example.org/> .
///                    ex:alice ex:name \"Alice\" ."
/// 
/// case turtle.parse(turtle_text) {
///   Ok(document) -> {
///     // Access document.base, document.prefixes, document.graph
///   }
///   Error(turtle.TurtleError(message, position)) -> {
///     // Handle parsing error with specific position
///   }
/// }
/// ```
pub fn parse(text: String) -> Result(TurtleDocument, TurtleError) {
  // One leading byte order mark is skipped, as the file readers do; any
  // other U+FEFF is a syntax error.
  tokenize(utf8.strip_bom(text))
  |> result.try(parse_tokens)
}

/// Parse a Turtle document and extract only the RDF graph content.
///
/// Convenience function that parses Turtle text and returns just the RDF graph,
/// discarding base IRI and prefix declarations. Useful when you only need the
/// actual RDF data without the document metadata.
///
/// ## Examples
/// ```gleam
/// let turtle_text = "@prefix ex: <http://example.org/> .
///                    ex:alice ex:name \"Alice\" ."
/// 
/// case turtle.parse_graph(turtle_text) {
///   Ok(rdf_graph) -> {
///     let triple_count = graph.size(rdf_graph)
///     // Work with the RDF graph directly
///   }
///   Error(error) -> // Handle parsing error
/// }
/// ```
pub fn parse_graph(text: String) -> Result(graph.Graph, TurtleError) {
  parse(text)
  |> result.map(fn(doc) { doc.graph })
}

/// Serialize a TurtleDocument to Turtle format text.
///
/// Converts a structured Turtle document back to valid Turtle syntax text.
/// Automatically handles IRI escaping, prefix usage, literal formatting, and
/// RDF 1.2 triple term serialization with `<<( s p o )>>` syntax. Output is
/// well-formatted and compliant with W3C Turtle specifications.
///
/// ## Examples
/// ```gleam
/// let turtle_text = turtle.serialize(my_document)
/// 
/// // Result might look like:
/// // @base <http://example.org/> .
/// // @prefix ex: <http://example.org/> .
/// // @prefix foaf: <http://xmlns.com/foaf/0.1/> .
/// // 
/// // ex:alice foaf:name "Alice" .
/// ```
pub fn serialize(document: TurtleDocument) -> String {
  serialize_document(document)
}

/// Serialize an RDF graph to Turtle format with custom base and prefixes.
///
/// Convenience function that creates a TurtleDocument from the provided
/// components and serializes it to Turtle text. Allows direct serialization
/// of RDF graphs with custom base IRI and prefix definitions without
/// manually constructing a TurtleDocument.
///
/// ## Examples
/// ```gleam
/// let prefixes = dict.from_list([
///   ("ex", "http://example.org/"),
///   ("foaf", "http://xmlns.com/foaf/0.1/")
/// ])
/// 
/// let turtle_text = turtle.serialize_graph(
///   my_rdf_graph,
///   Some("http://example.org/"),
///   prefixes
/// )
/// ```
pub fn serialize_graph(
  graph_value: graph.Graph,
  base: Option(String),
  prefixes: dict.Dict(String, String),
) -> String {
  serialize_document(TurtleDocument(
    base: base,
    prefixes: prefixes,
    graph: graph_value,
  ))
}

/// Parse a Turtle document from a file into a structured representation.
///
/// Reads a Turtle file and parses its contents including base declarations, 
/// prefix definitions, and RDF triples. Supports RDF 1.2 triple terms with
/// `<<( s p o )>>` syntax. Returns detailed error information on file read failures 
/// or parse errors.
///
/// ## Examples
/// ```gleam
/// case turtle.parse_file("data/ontology.ttl") {
///   Ok(document) -> {
///     // Access document.base, document.prefixes, document.graph
///     let triple_count = graph.size(document.graph)
///   }
///   Error(error) -> {
///     // Handle file read or parsing error
///   }
/// }
/// ```
pub fn parse_file(path: String) -> Result(TurtleDocument, TurtleError) {
  case utf8.read_file(path) {
    Ok(contents) -> parse(contents)
    Error(error) -> {
      let error_msg = case error {
        simplifile.Enoent -> "File not found"
        simplifile.Eacces -> "Permission denied"
        simplifile.Eisdir -> "Path is a directory"
        _ -> "File read error"
      }
      Error(TurtleError("File error: " <> error_msg <> " (" <> path <> ")", 0))
    }
  }
}

/// Parse a Turtle file and extract only the RDF graph content.
///
/// Convenience function that reads and parses a Turtle file, returning just 
/// the RDF graph while discarding base IRI and prefix declarations. Useful 
/// when you only need the actual RDF data from the file.
///
/// ## Examples
/// ```gleam
/// case turtle.parse_graph_file("data/triples.ttl") {
///   Ok(rdf_graph) -> {
///     let triple_count = graph.size(rdf_graph)
///     // Work with the RDF graph directly
///   }
///   Error(error) -> // Handle file or parsing error
/// }
/// ```
pub fn parse_graph_file(path: String) -> Result(graph.Graph, TurtleError) {
  parse_file(path)
  |> result.map(fn(doc) { doc.graph })
}

/// Serialize a TurtleDocument to a file in Turtle format.
///
/// Converts a structured Turtle document to valid Turtle syntax and writes 
/// it to the specified file. Creates parent directories if they don't exist.
/// Handles IRI escaping, prefix usage, literal formatting, and RDF-star 
/// quoted triple serialization.
///
/// ## Examples
/// ```gleam
/// let document = TurtleDocument(
///   base: Some("http://example.org/"),
///   prefixes: my_prefixes,
///   graph: my_graph
/// )
/// 
/// case turtle.serialize_to_file(document, "output/data.ttl") {
///   Ok(Nil) -> // File written successfully
///   Error(error) -> // Handle file write error
/// }
/// ```
pub fn serialize_to_file(
  document: TurtleDocument,
  path: String,
) -> Result(Nil, TurtleError) {
  let content = serialize_document(document)
  case simplifile.write(path, content) {
    Ok(Nil) -> Ok(Nil)
    Error(error) -> {
      let error_msg = case error {
        simplifile.Enoent -> "Directory not found"
        simplifile.Eacces -> "Permission denied"
        simplifile.Enospc -> "No space left on device"
        _ -> "File write error"
      }
      Error(TurtleError("File error: " <> error_msg <> " (" <> path <> ")", 0))
    }
  }
}

/// Serialize an RDF graph to a Turtle file with custom base and prefixes.
///
/// Convenience function that creates a TurtleDocument from the provided 
/// components and writes it to the specified file in Turtle format. Allows 
/// direct file output of RDF graphs with custom base IRI and prefix 
/// definitions without manually constructing a TurtleDocument.
///
/// ## Examples
/// ```gleam
/// let prefixes = dict.from_list([
///   ("ex", "http://example.org/"),
///   ("foaf", "http://xmlns.com/foaf/0.1/")
/// ])
/// 
/// case turtle.serialize_graph_to_file(
///   my_rdf_graph,
///   Some("http://example.org/"),
///   prefixes,
///   "output/graph.ttl"
/// ) {
///   Ok(Nil) -> // Graph written to file successfully
///   Error(error) -> // Handle file write error
/// }
/// ```
pub fn serialize_graph_to_file(
  graph_value: graph.Graph,
  base: Option(String),
  prefixes: dict.Dict(String, String),
  path: String,
) -> Result(Nil, TurtleError) {
  serialize_to_file(
    TurtleDocument(base: base, prefixes: prefixes, graph: graph_value),
    path,
  )
}

fn tokenize(text: String) -> Result(List(Token), TurtleError) {
  // The lexer works on codepoints, not grapheme clusters: the grammar is
  // defined on codepoints, and clusters (such as a combining accent after a
  // ':' or CR LF) would otherwise hide characters from the lexer.
  let chars =
    string.to_utf_codepoints(text)
    |> list.map(fn(codepoint) { string.from_utf_codepoints([codepoint]) })
  tokenize_loop(LexerState(chars, 0), [])
}

fn tokenize_loop(
  state: LexerState,
  acc: List(Token),
) -> Result(List(Token), TurtleError) {
  let state = skip_ws(state)
  case state {
    LexerState([], _) -> Ok(list.reverse(acc))
    _ ->
      next_token(state)
      |> result.try(fn(pair) {
        let #(token, state) = pair
        tokenize_loop(state, [token, ..acc])
      })
  }
}

fn next_token(state: LexerState) -> Result(#(Token, LexerState), TurtleError) {
  case state {
    LexerState(chars, pos) ->
      case chars {
        [] -> Error(TurtleError("Unexpected end of input", pos))
        ["@", ..rest] -> lex_directive_or_lang(LexerState(rest, pos + 1), pos)
        [".", next, ..] ->
          case is_ascii_digit(next) {
            True -> lex_number(state)
            False ->
              Ok(#(Token(Dot, pos), LexerState(list.drop(chars, 1), pos + 1)))
          }
        [".", ..rest] -> Ok(#(Token(Dot, pos), LexerState(rest, pos + 1)))
        [";", ..rest] -> Ok(#(Token(Semicolon, pos), LexerState(rest, pos + 1)))
        [",", ..rest] -> Ok(#(Token(Comma, pos), LexerState(rest, pos + 1)))
        ["^", ..rest] -> lex_hat(LexerState(rest, pos + 1), pos)
        ["<", "<", "(", ..rest] ->
          Ok(#(Token(TripleTermStart, pos), LexerState(rest, pos + 3)))
        ["<", "<", ..] ->
          Error(TurtleError(
            "Reified triples (<< ... >>) are not supported; write a triple term as <<( s p o )>>",
            pos,
          ))
        [")", ">", ">", ..rest] ->
          Ok(#(Token(TripleTermEnd, pos), LexerState(rest, pos + 3)))
        ["{", ..rest] ->
          Ok(#(Token(GraphStart, pos), LexerState(rest, pos + 1)))
        ["}", ..rest] -> Ok(#(Token(GraphEnd, pos), LexerState(rest, pos + 1)))
        ["<", ..] -> lex_iri(state)
        ["\"", "\"", "\"", ..rest] ->
          lex_string(LexerState(rest, pos + 3), pos, "\"", True)
        ["'", "'", "'", ..rest] ->
          lex_string(LexerState(rest, pos + 3), pos, "'", True)
        ["\"", ..rest] ->
          lex_string(LexerState(rest, pos + 1), pos, "\"", False)
        ["'", ..rest] -> lex_string(LexerState(rest, pos + 1), pos, "'", False)
        [":", ..] -> lex_prefixed_empty(state)
        ["_", ..rest] -> lex_blank(LexerState(rest, pos + 1), pos)
        [char, ..] ->
          case is_number_start(char) {
            True -> lex_number(state)
            False ->
              case turtle_names.is_prefix_start_char(char) {
                True -> lex_name_or_prefixed(state)
                False -> Error(TurtleError("Unexpected character", pos))
              }
          }
      }
  }
}

/// Lexes what follows an `@`: the `@prefix` / `@base` keywords, or a
/// `LANG_DIR` suffix (`en`, `en-US`, `en--ltr`). The suffix is validated by
/// the parser with `rdf_syntax.lang_dir_literal`, so all four formats report
/// the same errors.
fn lex_directive_or_lang(
  state: LexerState,
  pos: Int,
) -> Result(#(Token, LexerState), TurtleError) {
  take_while(state, is_lang_char)
  |> result.try(fn(pair) {
    let #(text, rest) = pair
    case text {
      "prefix" -> Ok(#(Token(PrefixDirective, pos), rest))
      "base" -> Ok(#(Token(BaseDirective, pos), rest))
      "" -> Error(TurtleError("Expected language tag", pos))
      _ -> Ok(#(Token(LangTag(text), pos), rest))
    }
  })
}

fn lex_hat(
  state: LexerState,
  pos: Int,
) -> Result(#(Token, LexerState), TurtleError) {
  case state {
    LexerState(chars, current) ->
      case chars {
        ["^", ..rest] ->
          Ok(#(Token(HatHat, pos), LexerState(rest, current + 1)))
        _ -> Error(TurtleError("Expected second ^", pos))
      }
  }
}

fn lex_iri(state: LexerState) -> Result(#(Token, LexerState), TurtleError) {
  let LexerState(_, pos) = state
  advance_char(state)
  |> result.try(fn(state2) {
    collect_iri(state2, [])
    |> result.map(fn(pair) {
      let #(value, state3) = pair
      #(Token(IriRef(value), pos), state3)
    })
  })
}

fn collect_iri(
  state: LexerState,
  acc: List(String),
) -> Result(#(String, LexerState), TurtleError) {
  case state {
    LexerState(chars, pos) ->
      case list.is_empty(chars) {
        True -> Error(TurtleError("Unterminated IRI", pos))
        False ->
          case chars {
            [">", ..rest] ->
              Ok(#(string.concat(list.reverse(acc)), LexerState(rest, pos + 1)))
            ["\\", ..rest] ->
              parse_escape(LexerState(rest, pos + 1))
              |> result.try(fn(pair) {
                let #(char, state) = pair
                collect_iri(state, [char, ..acc])
              })
            [char, ..rest] ->
              collect_iri(LexerState(rest, pos + 1), [char, ..acc])
            [] -> Error(TurtleError("Unterminated IRI", pos))
          }
      }
  }
}

/// Lexes a string body after its opening quote (`"`, `'`, `"""` or `'''`).
/// `pos` is the position of the opening quote.
fn lex_string(
  state: LexerState,
  pos: Int,
  quote: String,
  long: Bool,
) -> Result(#(Token, LexerState), TurtleError) {
  let collected = case long {
    True -> collect_long_string(state, quote, [])
    False -> collect_string(state, quote, [])
  }
  collected
  |> result.map(fn(pair) {
    let #(value, state) = pair
    #(Token(StringLiteral(value), pos), state)
  })
}

/// `STRING_LITERAL_QUOTE` / `STRING_LITERAL_SINGLE_QUOTE`: no raw line
/// breaks.
fn collect_string(
  state: LexerState,
  quote: String,
  acc: List(String),
) -> Result(#(String, LexerState), TurtleError) {
  let LexerState(chars, pos) = state
  case chars {
    [char, ..rest] if char == quote ->
      Ok(#(string.concat(list.reverse(acc)), LexerState(rest, pos + 1)))
    ["\\", ..rest] ->
      parse_escape(LexerState(rest, pos + 1))
      |> result.try(fn(pair) {
        let #(char, state) = pair
        collect_string(state, quote, [char, ..acc])
      })
    ["\n", ..] | ["\r", ..] ->
      Error(TurtleError("Line break not allowed in string", pos))
    [char, ..rest] ->
      collect_string(LexerState(rest, pos + 1), quote, [char, ..acc])
    [] -> Error(TurtleError("Unterminated string", pos))
  }
}

/// `STRING_LITERAL_LONG_QUOTE` / `STRING_LITERAL_LONG_SINGLE_QUOTE`: ends at
/// the first three unescaped quotes; raw line breaks are allowed.
fn collect_long_string(
  state: LexerState,
  quote: String,
  acc: List(String),
) -> Result(#(String, LexerState), TurtleError) {
  let LexerState(chars, pos) = state
  case chars {
    [a, b, c, ..rest] if a == quote && b == quote && c == quote ->
      Ok(#(string.concat(list.reverse(acc)), LexerState(rest, pos + 3)))
    ["\\", ..rest] ->
      parse_escape(LexerState(rest, pos + 1))
      |> result.try(fn(pair) {
        let #(char, state) = pair
        collect_long_string(state, quote, [char, ..acc])
      })
    [char, ..rest] ->
      collect_long_string(LexerState(rest, pos + 1), quote, [char, ..acc])
    [] -> Error(TurtleError("Unterminated long string", pos))
  }
}

fn parse_escape(
  state: LexerState,
) -> Result(#(String, LexerState), TurtleError) {
  case state {
    LexerState(chars, pos) ->
      case list.is_empty(chars) {
        True -> Error(TurtleError("Invalid escape", pos))
        False ->
          case chars {
            [char, ..rest] ->
              case char {
                "t" -> Ok(#("\t", LexerState(rest, pos + 1)))
                "n" -> Ok(#("\n", LexerState(rest, pos + 1)))
                "r" -> Ok(#("\r", LexerState(rest, pos + 1)))
                "b" -> Ok(#("\u{0008}", LexerState(rest, pos + 1)))
                "f" -> Ok(#("\u{000C}", LexerState(rest, pos + 1)))
                "\"" -> Ok(#("\"", LexerState(rest, pos + 1)))
                "'" -> Ok(#("'", LexerState(rest, pos + 1)))
                "\\" -> Ok(#("\\", LexerState(rest, pos + 1)))
                "u" -> parse_unicode(LexerState(rest, pos + 1), 4)
                "U" -> parse_unicode(LexerState(rest, pos + 1), 8)
                _ -> Error(TurtleError("Unsupported escape", pos))
              }
            [] -> Error(TurtleError("Invalid escape", pos))
          }
      }
  }
}

fn parse_unicode(
  state: LexerState,
  digits: Int,
) -> Result(#(String, LexerState), TurtleError) {
  take_exact(state, digits, is_hex_digit)
  |> result.try(fn(pair) {
    let #(hex, state2) = pair
    let LexerState(_, error_pos) = state2
    int.base_parse(hex, 16)
    |> result.map_error(fn(_) {
      TurtleError("Invalid unicode escape", error_pos)
    })
    |> result.try(fn(value) {
      string.utf_codepoint(value)
      |> result.map_error(fn(_) {
        TurtleError("Invalid unicode escape", error_pos)
      })
      |> result.map(fn(cp) { #(string.from_utf_codepoints([cp]), state2) })
    })
  })
}

fn lex_prefixed_empty(
  state: LexerState,
) -> Result(#(Token, LexerState), TurtleError) {
  let LexerState(_, pos) = state
  advance_char(state)
  |> result.try(lex_local)
  |> result.map(fn(pair) {
    let #(local, state) = pair
    #(Token(Prefixed("", local), pos), state)
  })
}

fn lex_blank(
  state: LexerState,
  pos: Int,
) -> Result(#(Token, LexerState), TurtleError) {
  case state {
    LexerState(chars, _) ->
      case chars {
        [":", ..rest] -> {
          // A label may contain '.' but never ends with one: a trailing '.'
          // is the statement terminator.
          let #(label, state) = lex_blank_label(LexerState(rest, pos + 2), [])
          case label {
            "" -> Error(TurtleError("Expected blank node label", pos))
            _ -> #(Token(BlankLabel(label), pos - 1), state) |> Ok
          }
        }
        _ -> Error(TurtleError("Invalid blank node", pos))
      }
  }
}

/// Lexes the longest `INTEGER`, `DECIMAL` or `DOUBLE` at the cursor. A '.'
/// not followed by a digit or an exponent ends the statement instead.
fn lex_blank_label(
  state: LexerState,
  acc: List(String),
) -> #(String, LexerState) {
  case state {
    LexerState([char, ..rest], pos) ->
      case is_name_char(char) || { acc != [] && char == "." } {
        True -> lex_blank_label(LexerState(rest, pos + 1), [char, ..acc])
        False -> give_back_trailing_dots(acc, state)
      }
    LexerState([], _) -> give_back_trailing_dots(acc, state)
  }
}

fn lex_number(state: LexerState) -> Result(#(Token, LexerState), TurtleError) {
  let LexerState(chars, pos) = state
  case turtle_names.scan_number(chars) {
    Ok(#(kind, length)) -> {
      let text = string.concat(list.take(chars, length))
      Ok(#(
        Token(NumberLiteral(kind, text), pos),
        LexerState(list.drop(chars, length), pos + length),
      ))
    }
    Error(Nil) -> Error(TurtleError("Invalid number", pos))
  }
}

fn lex_name_or_prefixed(
  state: LexerState,
) -> Result(#(Token, LexerState), TurtleError) {
  let LexerState(_, pos) = state
  let #(name, state) = lex_prefix_name(state, [])
  case state {
    LexerState([":", ..rest], next_pos) ->
      lex_local(LexerState(rest, next_pos + 1))
      |> result.map(fn(pair) {
        let #(local, state) = pair
        #(Token(Prefixed(name, local), pos), state)
      })
    _ ->
      // Turtle keywords other than PREFIX and BASE are case-sensitive.
      case name {
        "true" -> Ok(#(Token(BooleanLiteral(True), pos), state))
        "false" -> Ok(#(Token(BooleanLiteral(False), pos), state))
        _ -> Ok(#(Token(Word(name), pos), state))
      }
  }
}

/// Reads the rest of a PN_PREFIX (or a keyword) after its first character
/// was checked. Trailing dots are left for the next token.
fn lex_prefix_name(
  state: LexerState,
  acc: List(String),
) -> #(String, LexerState) {
  case state {
    LexerState([char, ..rest], pos) ->
      case acc == [] || turtle_names.is_prefix_char(char) {
        True -> lex_prefix_name(LexerState(rest, pos + 1), [char, ..acc])
        False -> give_back_trailing_dots(acc, state)
      }
    LexerState([], _) -> give_back_trailing_dots(acc, state)
  }
}

fn give_back_trailing_dots(
  acc: List(String),
  state: LexerState,
) -> #(String, LexerState) {
  case acc {
    [".", ..rest] -> {
      let LexerState(chars, pos) = state
      give_back_trailing_dots(rest, LexerState([".", ..chars], pos - 1))
    }
    _ -> #(string.concat(list.reverse(acc)), state)
  }
}

/// A decoded piece of a local name, whether it was an unescaped '.', and the
/// lexer state before it (to give trailing dots back to the next token).
type LocalPiece {
  LocalPiece(text: String, bare_dot: Bool, before: LexerState)
}

/// Reads a PN_LOCAL (possibly empty) after the ':' of a prefixed name.
/// `PN_LOCAL_ESC` escapes are decoded (`\/` is '/'), while `%XX` sequences are
/// kept as they are, as the Turtle grammar requires.
fn lex_local(state: LexerState) -> Result(#(String, LexerState), TurtleError) {
  lex_local_loop(state, [])
}

fn lex_local_loop(
  state: LexerState,
  acc: List(LocalPiece),
) -> Result(#(String, LexerState), TurtleError) {
  let LexerState(chars, pos) = state
  case chars {
    ["%", high, low, ..rest] ->
      case is_hex_digit(high) && is_hex_digit(low) {
        True ->
          lex_local_loop(LexerState(rest, pos + 3), [
            LocalPiece("%" <> high <> low, False, state),
            ..acc
          ])
        False -> Error(TurtleError("Invalid percent escape in local name", pos))
      }
    ["%", ..] -> Error(TurtleError("Invalid percent escape in local name", pos))
    ["\\", char, ..rest] ->
      case turtle_names.is_local_escape_char(char) {
        True ->
          lex_local_loop(LexerState(rest, pos + 2), [
            LocalPiece(char, False, state),
            ..acc
          ])
        False -> Error(TurtleError("Invalid escape in local name", pos))
      }
    ["\\"] -> Error(TurtleError("Invalid escape in local name", pos))
    [char, ..rest] -> {
      let accepted = case acc {
        [] -> turtle_names.is_local_start_char(char)
        _ -> char == "." || turtle_names.is_local_char(char)
      }
      case accepted {
        True ->
          lex_local_loop(LexerState(rest, pos + 1), [
            LocalPiece(char, char == ".", state),
            ..acc
          ])
        False -> Ok(finish_local(acc, state))
      }
    }
    [] -> Ok(finish_local(acc, state))
  }
}

fn finish_local(
  acc: List(LocalPiece),
  state: LexerState,
) -> #(String, LexerState) {
  case acc {
    [LocalPiece(bare_dot: True, before:, ..), ..rest] ->
      finish_local(rest, before)
    _ -> #(
      acc |> list.map(fn(piece) { piece.text }) |> list.reverse |> string.concat,
      state,
    )
  }
}

fn skip_ws(state: LexerState) -> LexerState {
  case state {
    LexerState(chars, pos) ->
      case chars {
        [] -> state
        [" ", ..rest] -> skip_ws(LexerState(rest, pos + 1))
        ["\t", ..rest] -> skip_ws(LexerState(rest, pos + 1))
        ["\r", ..rest] -> skip_ws(LexerState(rest, pos + 1))
        ["\n", ..rest] -> skip_ws(LexerState(rest, pos + 1))
        ["#", ..rest] -> skip_comment(LexerState(rest, pos + 1))
        _ -> state
      }
  }
}

fn skip_comment(state: LexerState) -> LexerState {
  case state {
    LexerState(chars, pos) ->
      case chars {
        [] -> state
        ["\n", ..rest] -> skip_ws(LexerState(rest, pos + 1))
        ["\r", ..rest] -> skip_ws(LexerState(rest, pos + 1))
        [_any, ..rest] -> skip_comment(LexerState(rest, pos + 1))
      }
  }
}

fn advance_char(state: LexerState) -> Result(LexerState, TurtleError) {
  case state {
    LexerState(chars, pos) ->
      case chars {
        [] -> Error(TurtleError("Unexpected end of input", pos))
        [_any, ..rest] -> Ok(LexerState(rest, pos + 1))
      }
  }
}

fn take_while(
  state: LexerState,
  predicate: fn(String) -> Bool,
) -> Result(#(String, LexerState), TurtleError) {
  take_while_loop(state, predicate, [])
}

fn take_while_loop(
  state: LexerState,
  predicate: fn(String) -> Bool,
  acc: List(String),
) -> Result(#(String, LexerState), TurtleError) {
  case state {
    LexerState(chars, pos) ->
      case chars {
        [] -> Ok(#(string.concat(list.reverse(acc)), state))
        [char, ..rest] ->
          case predicate(char) {
            True ->
              take_while_loop(LexerState(rest, pos + 1), predicate, [
                char,
                ..acc
              ])
            False -> Ok(#(string.concat(list.reverse(acc)), state))
          }
      }
  }
}

fn take_exact(
  state: LexerState,
  count: Int,
  predicate: fn(String) -> Bool,
) -> Result(#(String, LexerState), TurtleError) {
  take_exact_loop(state, count, predicate, [])
}

fn take_exact_loop(
  state: LexerState,
  count: Int,
  predicate: fn(String) -> Bool,
  acc: List(String),
) -> Result(#(String, LexerState), TurtleError) {
  case count {
    0 -> Ok(#(string.concat(list.reverse(acc)), state))
    _ ->
      case state {
        LexerState(chars, pos) ->
          case chars {
            [] -> Error(TurtleError("Unexpected end of input", pos))
            [char, ..rest] ->
              case predicate(char) {
                True ->
                  take_exact_loop(
                    LexerState(rest, pos + 1),
                    count - 1,
                    predicate,
                    [char, ..acc],
                  )
                False -> Error(TurtleError("Invalid character", pos))
              }
          }
      }
  }
}

fn is_number_start(char: String) -> Bool {
  string.contains("0123456789+-", char)
}

fn is_name_start(char: String) -> Bool {
  let lower = string.lowercase(char)
  string.contains("abcdefghijklmnopqrstuvwxyz", lower) || char == "_"
}

fn is_name_char(char: String) -> Bool {
  is_name_start(char) || string.contains("0123456789-", char)
}

/// Characters of a `LANG_DIR` suffix: ASCII letters, digits and `-`.
fn is_lang_char(char: String) -> Bool {
  char == "-" || is_ascii_letter(char) || is_ascii_digit(char)
}

fn is_hex_digit(char: String) -> Bool {
  string.contains("0123456789abcdefABCDEF", char)
}

/// Which grammar the statement parser follows: TriG adds graph blocks.
type Syntax {
  TurtleSyntax
  TrigSyntax
}

/// The directives in effect and the statements read so far (in reverse
/// order while parsing).
type Statements {
  Statements(
    base: Option(String),
    prefixes: dict.Dict(String, String),
    quads: List(statement.Quad),
  )
}

fn parse_tokens(tokens: List(Token)) -> Result(TurtleDocument, TurtleError) {
  parse_statements(
    ParserState(tokens),
    TurtleSyntax,
    Statements(None, dict.new(), []),
  )
  |> result.map(fn(parsed) {
    TurtleDocument(
      base: parsed.base,
      prefixes: parsed.prefixes,
      graph: graph.from_list(list.map(parsed.quads, statement.triple_from_quad)),
    )
  })
}

/// Parse a TriG document into its base, prefixes and quads. This is the
/// Turtle parser with TriG graph blocks (`{ ... }`, `label { ... }` and
/// `GRAPH label { ... }`) enabled; the TriG module wraps it in its own
/// document and error types. One leading byte order mark is skipped.
///
/// ## Examples
/// ```gleam
/// parse_trig("<http://ex.org/g> { <http://ex.org/s> <http://ex.org/p> \"o\"@en--ltr }")
/// // -> Ok(#(None, dict.new(), [quad in graph <http://ex.org/g>]))
/// ```
@internal
pub fn parse_trig(
  text: String,
) -> Result(
  #(Option(String), dict.Dict(String, String), List(statement.Quad)),
  TurtleError,
) {
  tokenize(utf8.strip_bom(text))
  |> result.try(fn(tokens) {
    parse_statements(
      ParserState(tokens),
      TrigSyntax,
      Statements(None, dict.new(), []),
    )
  })
  |> result.map(fn(parsed) { #(parsed.base, parsed.prefixes, parsed.quads) })
}

/// Reads directives and statements until the input ends. Directives may
/// appear between statements and apply to everything after them.
fn parse_statements(
  state: ParserState,
  syntax: Syntax,
  parsed: Statements,
) -> Result(Statements, TurtleError) {
  case peek(state), syntax {
    None, _ -> Ok(Statements(..parsed, quads: list.reverse(parsed.quads)))
    Some(Token(PrefixDirective, _)), _ ->
      parse_prefix(pop(state))
      |> result.try(fn(found) {
        let #(prefix, iri, state) = found
        let prefixes = dict.insert(parsed.prefixes, prefix, iri)
        parse_statements(state, syntax, Statements(..parsed, prefixes:))
      })
    Some(Token(BaseDirective, _)), _ ->
      parse_base(pop(state))
      |> result.try(fn(found) {
        let #(iri, state) = found
        parse_statements(state, syntax, Statements(..parsed, base: Some(iri)))
      })
    Some(Token(GraphStart, _)), TrigSyntax ->
      parse_graph_block(drop_one(state), term.DefaultGraph, parsed)
      |> result.try(fn(found) {
        let #(parsed, state) = found
        parse_statements(state, syntax, parsed)
      })
    Some(Token(Word(word), pos)), TrigSyntax ->
      case string.uppercase(word) {
        "GRAPH" -> parse_labelled_graph(drop_one(state), syntax, parsed)
        _ -> Error(TurtleError("Expected subject", pos))
      }
    Some(_), TrigSyntax ->
      case state {
        ParserState([_, Token(GraphStart, _), ..]) ->
          parse_labelled_graph(state, syntax, parsed)
        _ -> parse_default_statement(state, syntax, parsed)
      }
    Some(_), TurtleSyntax -> parse_default_statement(state, syntax, parsed)
  }
}

/// A `triples '.'` statement outside any graph block.
fn parse_default_statement(
  state: ParserState,
  syntax: Syntax,
  parsed: Statements,
) -> Result(Statements, TurtleError) {
  parse_triples_statement(state, parsed.base, parsed.prefixes)
  |> result.try(fn(found) {
    let #(triples, state) = found
    consume_dot(state)
    |> result.try(fn(state) {
      let parsed = add_quads(parsed, triples, term.DefaultGraph)
      parse_statements(state, syntax, parsed)
    })
  })
}

/// `label { ... }` (the optional `GRAPH` keyword already consumed).
fn parse_labelled_graph(
  state: ParserState,
  syntax: Syntax,
  parsed: Statements,
) -> Result(Statements, TurtleError) {
  consume_token(state, fn(token) {
    graph_label(token, parsed.base, parsed.prefixes)
  })
  |> result.try(fn(found) {
    let #(name, state) = found
    consume_token(state, fn(token) {
      case token {
        Token(GraphStart, _) -> Ok(Nil)
        _ ->
          Error(TurtleError(
            "Expected '{' after the graph name",
            token_position(token),
          ))
      }
    })
    |> result.try(fn(found) {
      let #(_, state) = found
      parse_graph_block(state, name, parsed)
    })
    |> result.try(fn(found) {
      let #(parsed, state) = found
      parse_statements(state, syntax, parsed)
    })
  })
}

fn graph_label(
  token: Token,
  base: Option(String),
  prefixes: dict.Dict(String, String),
) -> Result(term.GraphName, TurtleError) {
  case token {
    Token(IriRef(iri), pos) ->
      apply_base(iri, base, pos)
      |> result.try(fn(resolved) {
        term.named_node(resolved)
        |> result.map_error(fn(_) { TurtleError("Invalid graph name", pos) })
      })
      |> result.map(term.NamedGraph)
    Token(Prefixed(prefix, local), pos) ->
      resolve_prefixed(prefixes, prefix, local, pos)
      |> result.try(fn(iri) {
        term.named_node(iri)
        |> result.map_error(fn(_) { TurtleError("Invalid graph name", pos) })
      })
      |> result.map(term.NamedGraph)
    Token(BlankLabel(label), pos) ->
      term.blank_node(label)
      |> result.map_error(fn(_) { TurtleError("Invalid blank node", pos) })
      |> result.map(term.BlankGraph)
    _ -> Error(TurtleError("Expected graph name", token_position(token)))
  }
}

/// The statements of a graph block after its `{`, up to and including the
/// `}`. The `.` after the last statement is optional.
fn parse_graph_block(
  state: ParserState,
  name: term.GraphName,
  parsed: Statements,
) -> Result(#(Statements, ParserState), TurtleError) {
  case peek(state) {
    Some(Token(GraphEnd, _)) -> Ok(#(parsed, drop_one(state)))
    None -> Error(TurtleError("Expected '}' to close the graph block", -1))
    Some(_) ->
      parse_triples_statement(state, parsed.base, parsed.prefixes)
      |> result.try(fn(found) {
        let #(triples, state) = found
        let parsed = add_quads(parsed, triples, name)
        case peek(state) {
          Some(Token(Dot, _)) ->
            parse_graph_block(drop_one(state), name, parsed)
          Some(Token(GraphEnd, _)) -> Ok(#(parsed, drop_one(state)))
          Some(token) ->
            Error(TurtleError("Expected '.' or '}'", token_position(token)))
          None ->
            Error(TurtleError("Expected '}' to close the graph block", -1))
        }
      })
  }
}

fn add_quads(
  parsed: Statements,
  triples: List(statement.Triple),
  name: term.GraphName,
) -> Statements {
  let quads = list.map(triples, statement.quad(_, name))
  Statements(..parsed, quads: list.append(quads, parsed.quads))
}

fn parse_prefix(
  state_result: Result(#(Token, ParserState), TurtleError),
) -> Result(#(String, String, ParserState), TurtleError) {
  state_result
  |> result.try(fn(pair) {
    let #(_, state) = pair
    consume_token(state, fn(token) {
      case token {
        Token(PrefixLabel(label), _) -> Ok(label)
        // The grammar wants PNAME_NS here: a label and ':' with no local
        // part, so `@prefix ex:a <...>` is a syntax error.
        Token(Prefixed(prefix, ""), _) -> Ok(prefix)
        Token(Prefixed(_, _), pos) ->
          Error(TurtleError(
            "Expected a prefix label ending in ':' with no local name",
            pos,
          ))
        _ -> Error(TurtleError("Expected prefix label", token_position(token)))
      }
    })
    |> result.try(fn(pair2) {
      let #(label, state) = pair2
      consume_token(state, expect_iri)
      |> result.try(fn(pair3) {
        let #(iri, state) = pair3
        consume_dot(state)
        |> result.map(fn(state) { #(label, iri, state) })
      })
    })
  })
}

fn parse_base(
  state_result: Result(#(Token, ParserState), TurtleError),
) -> Result(#(String, ParserState), TurtleError) {
  state_result
  |> result.try(fn(pair) {
    let #(_, state) = pair
    consume_token(state, expect_iri)
    |> result.try(fn(pair2) {
      let #(iri, state) = pair2
      consume_dot(state)
      |> result.map(fn(state) { #(iri, state) })
    })
  })
}

/// `subject predicateObjectList`, without the terminating `.`.
fn parse_triples_statement(
  state: ParserState,
  base: Option(String),
  prefixes: dict.Dict(String, String),
) -> Result(#(List(statement.Triple), ParserState), TurtleError) {
  parse_subject(state, base, prefixes)
  |> result.try(fn(pair) {
    let #(subject, state) = pair
    parse_predicate_object_list(state, subject, base, prefixes, [])
  })
}

fn parse_predicate_object_list(
  state: ParserState,
  subject: term.Subject,
  base: Option(String),
  prefixes: dict.Dict(String, String),
  acc: List(statement.Triple),
) -> Result(#(List(statement.Triple), ParserState), TurtleError) {
  parse_predicate(state, base, prefixes)
  |> result.try(fn(pair) {
    let #(predicate, state) = pair
    parse_object_list(state, base, prefixes, [])
    |> result.try(fn(pair2) {
      let #(objects, state) = pair2
      let triples =
        objects
        |> list.map(fn(object) { statement.triple(subject, predicate, object) })
      let combined = list.append(triples, acc)
      case consume_if(state, Semicolon) {
        Ok(#(True, state)) ->
          case peek(state) {
            Some(Token(Dot, _))
            | Some(Token(Semicolon, _))
            | Some(Token(GraphEnd, _))
            | None -> Ok(#(combined, state))
            _ ->
              parse_predicate_object_list(
                state,
                subject,
                base,
                prefixes,
                combined,
              )
          }
        Ok(#(False, state)) -> Ok(#(combined, state))
        Error(err) -> Error(err)
      }
    })
  })
}

fn parse_object_list(
  state: ParserState,
  base: Option(String),
  prefixes: dict.Dict(String, String),
  acc: List(term.Object),
) -> Result(#(List(term.Object), ParserState), TurtleError) {
  parse_object(state, base, prefixes)
  |> result.try(fn(pair) {
    let #(object, state) = pair
    let acc = [object, ..acc]
    case consume_if(state, Comma) {
      Ok(#(True, state)) -> parse_object_list(state, base, prefixes, acc)
      Ok(#(False, state)) -> Ok(#(list.reverse(acc), state))
      Error(err) -> Error(err)
    }
  })
}

fn parse_subject(
  state: ParserState,
  base: Option(String),
  prefixes: dict.Dict(String, String),
) -> Result(#(term.Subject, ParserState), TurtleError) {
  use <- triple_term_or(state, base, prefixes, term.SubjectTriple)
  consume_token(state, fn(token) {
    case token {
      Token(IriRef(iri), pos) ->
        apply_base(iri, base, pos)
        |> result.try(fn(resolved) {
          term.named_node(resolved)
          |> result.map_error(fn(_) { TurtleError("Invalid IRI", pos) })
          |> result.map(fn(node) { term.SubjectNamed(node) })
        })
      Token(Prefixed(prefix, local), pos) ->
        resolve_prefixed(prefixes, prefix, local, pos)
        |> result.try(fn(iri) {
          term.named_node(iri)
          |> result.map_error(fn(_) { TurtleError("Invalid prefixed IRI", pos) })
          |> result.map(fn(node) { term.SubjectNamed(node) })
        })
      Token(BlankLabel(label), pos) ->
        term.blank_node(label)
        |> result.map_error(fn(_) { TurtleError("Invalid blank node", pos) })
        |> result.map(fn(node) { term.SubjectBlank(node) })
      token -> Error(TurtleError("Expected subject", token_position(token)))
    }
  })
}

fn parse_predicate(
  state: ParserState,
  base: Option(String),
  prefixes: dict.Dict(String, String),
) -> Result(#(term.Predicate, ParserState), TurtleError) {
  consume_token(state, fn(token) {
    case token {
      Token(Word(word), pos) ->
        case word {
          "a" ->
            term.named_node(rdf_type)
            |> result.map_error(fn(_) { TurtleError("Invalid rdf:type", 0) })
          _ -> Error(TurtleError("Expected predicate", pos))
        }
      Token(IriRef(iri), pos) ->
        apply_base(iri, base, pos)
        |> result.try(fn(resolved) {
          term.named_node(resolved)
          |> result.map_error(fn(_) { TurtleError("Invalid predicate", pos) })
        })
      Token(Prefixed(prefix, local), pos) ->
        resolve_prefixed(prefixes, prefix, local, pos)
        |> result.try(fn(iri) {
          term.named_node(iri)
          |> result.map_error(fn(_) { TurtleError("Invalid predicate", pos) })
        })
      token -> Error(TurtleError("Expected predicate", token_position(token)))
    }
  })
}

/// Parses a triple term `<<( subject predicate object )>>` when one starts
/// at the head of `state` and wraps it with `wrap`; otherwise runs
/// `otherwise`. Like the N-Triples parser, triple terms are accepted as
/// subjects as well as objects, and they may nest.
fn triple_term_or(
  state: ParserState,
  base: Option(String),
  prefixes: dict.Dict(String, String),
  wrap: fn(term.TripleTerm) -> a,
  otherwise: fn() -> Result(#(a, ParserState), TurtleError),
) -> Result(#(a, ParserState), TurtleError) {
  case peek(state) {
    Some(Token(TripleTermStart, _)) -> {
      use #(subject, state) <- result.try(parse_subject(
        drop_one(state),
        base,
        prefixes,
      ))
      use #(predicate, state) <- result.try(parse_predicate(
        state,
        base,
        prefixes,
      ))
      use #(object, state) <- result.try(parse_object(state, base, prefixes))
      use #(_, state) <- result.map(
        consume_token(state, fn(token) {
          case token {
            Token(TripleTermEnd, _) -> Ok(Nil)
            _ ->
              Error(TurtleError(
                "Expected ')>>' to close the triple term",
                token_position(token),
              ))
          }
        }),
      )
      #(wrap(term.triple_term(subject, predicate, object)), state)
    }
    _ -> otherwise()
  }
}

/// The optional `LANG_DIR` or `^^datatype` suffix after a string.
fn parse_post_string(
  value: String,
  state: ParserState,
  base: Option(String),
  prefixes: dict.Dict(String, String),
) -> Result(#(term.Object, ParserState), TurtleError) {
  case peek(state) {
    Some(Token(LangTag(lang_dir), tag_pos)) ->
      rdf_syntax.lang_dir_literal(value, lang_dir)
      |> result.map_error(TurtleError(_, tag_pos))
      |> result.map(fn(literal) {
        #(term.ObjectLiteral(literal), drop_one(state))
      })
    Some(Token(HatHat, _)) ->
      consume_token(drop_one(state), fn(token) {
        case token {
          Token(IriRef(iri), pos) ->
            apply_base(iri, base, pos)
            |> result.try(fn(resolved) {
              term.named_node(resolved)
              |> result.map_error(fn(_) { TurtleError("Invalid datatype", pos) })
            })
          Token(Prefixed(prefix, local), pos) ->
            resolve_prefixed(prefixes, prefix, local, pos)
            |> result.try(fn(iri) {
              term.named_node(iri)
              |> result.map_error(fn(_) { TurtleError("Invalid datatype", pos) })
            })
          _ ->
            Error(TurtleError("Expected datatype IRI", token_position(token)))
        }
        |> result.try(fn(datatype) {
          rdf_syntax.typed_literal(value, datatype)
          |> result.map(term.ObjectLiteral)
          |> result.map_error(TurtleError(_, token_position(token)))
        })
      })
    _ -> Ok(#(term.ObjectLiteral(term.SimpleLiteral(value)), state))
  }
}

fn number_literal(kind: NumberKind, text: String) -> term.Object {
  let datatype = case kind {
    IntegerNumber -> term.unsafe_named_node(xsd_integer)
    DecimalNumber -> term.unsafe_named_node(xsd_decimal)
    DoubleNumber -> term.unsafe_named_node(xsd_double)
  }
  term.ObjectLiteral(term.TypedLiteral(text, datatype))
}

fn boolean_literal(value: Bool) -> term.Object {
  let datatype = term.unsafe_named_node(xsd_boolean)
  let text = case value {
    True -> "true"
    False -> "false"
  }
  term.ObjectLiteral(term.TypedLiteral(text, datatype))
}

fn consume_dot(state: ParserState) -> Result(ParserState, TurtleError) {
  consume_token(state, fn(token) {
    case token {
      Token(Dot, _) -> Ok(Nil)
      _ -> Error(TurtleError("Expected '.'", token_position(token)))
    }
  })
  |> result.map(fn(pair) {
    let #(_, state) = pair
    state
  })
}

// Removed unused consume_prefix_label

fn expect_iri(token: Token) -> Result(String, TurtleError) {
  case token {
    Token(IriRef(iri), _) -> Ok(iri)
    _ -> Error(TurtleError("Expected IRI", token_position(token)))
  }
}

fn parse_object(
  state: ParserState,
  base: Option(String),
  prefixes: dict.Dict(String, String),
) -> Result(#(term.Object, ParserState), TurtleError) {
  use <- triple_term_or(state, base, prefixes, term.ObjectTriple)
  pop(state)
  |> result.try(fn(pair) {
    let #(token, state_after) = pair
    case token {
      Token(IriRef(iri), pos) ->
        apply_base(iri, base, pos)
        |> result.try(fn(resolved) {
          term.named_node(resolved)
          |> result.map_error(fn(_) { TurtleError("Invalid IRI", pos) })
          |> result.map(fn(node) { #(term.ObjectNamed(node), state_after) })
        })
      Token(Prefixed(prefix, local), pos) ->
        resolve_prefixed(prefixes, prefix, local, pos)
        |> result.try(fn(iri) {
          term.named_node(iri)
          |> result.map_error(fn(_) { TurtleError("Invalid prefixed IRI", pos) })
          |> result.map(fn(node) { #(term.ObjectNamed(node), state_after) })
        })
      Token(BlankLabel(label), pos) ->
        term.blank_node(label)
        |> result.map_error(fn(_) { TurtleError("Invalid blank node", pos) })
        |> result.map(fn(node) { #(term.ObjectBlank(node), state_after) })
      Token(StringLiteral(value), _) ->
        parse_post_string(value, state_after, base, prefixes)
      Token(NumberLiteral(kind, text), _) ->
        Ok(#(number_literal(kind, text), state_after))
      Token(BooleanLiteral(value), _) ->
        Ok(#(boolean_literal(value), state_after))
      token -> Error(TurtleError("Unsupported object", token_position(token)))
    }
  })
}

fn consume_if(
  state: ParserState,
  expected: TokenKind,
) -> Result(#(Bool, ParserState), TurtleError) {
  case state {
    ParserState([]) -> Ok(#(False, state))
    ParserState([Token(kind, _), ..rest]) ->
      case keyword_matches(kind, expected) {
        True -> Ok(#(True, ParserState(rest)))
        False -> Ok(#(False, state))
      }
  }
}

fn keyword_matches(actual: TokenKind, expected: TokenKind) -> Bool {
  case actual {
    Dot ->
      case expected {
        Dot -> True
        _ -> False
      }
    Semicolon ->
      case expected {
        Semicolon -> True
        _ -> False
      }
    Comma ->
      case expected {
        Comma -> True
        _ -> False
      }
    _ -> False
  }
}

fn peek(state: ParserState) -> Option(Token) {
  case state {
    ParserState([]) -> None
    ParserState([token, ..]) -> Some(token)
  }
}

fn pop(state: ParserState) -> Result(#(Token, ParserState), TurtleError) {
  case state {
    ParserState([]) -> Error(TurtleError("Unexpected end of input", -1))
    ParserState([token, ..rest]) -> Ok(#(token, ParserState(rest)))
  }
}

fn consume_token(
  state: ParserState,
  extractor: fn(Token) -> Result(a, TurtleError),
) -> Result(#(a, ParserState), TurtleError) {
  pop(state)
  |> result.try(fn(pair) {
    let #(token, state) = pair
    extractor(token)
    |> result.map(fn(value) { #(value, state) })
  })
}

fn drop_one(state: ParserState) -> ParserState {
  case state {
    ParserState([]) -> state
    ParserState([_, ..rest]) -> ParserState(rest)
  }
}

fn token_position(token: Token) -> Int {
  let Token(_, position) = token
  position
}

fn resolve_prefixed(
  prefixes: dict.Dict(String, String),
  prefix: String,
  local: String,
  pos: Int,
) -> Result(String, TurtleError) {
  case dict.get(prefixes, prefix) {
    Ok(ns) -> Ok(ns <> local)
    Error(_) -> Error(TurtleError("Unknown prefix", pos))
  }
}

fn apply_base(
  iri: String,
  base: Option(String),
  _pos: Int,
) -> Result(String, TurtleError) {
  case base {
    None -> Ok(iri)
    Some(base_iri) -> {
      let reference = parse_iri_reference(iri)
      case reference.scheme {
        Some(_) -> Ok(iri)
        None ->
          Ok(
            recompose_iri(resolve_reference(
              parse_iri_reference(base_iri),
              reference,
            )),
          )
      }
    }
  }
}

/// The five components of an IRI reference (RFC 3986 section 3).
type IriReference {
  IriReference(
    scheme: Option(String),
    authority: Option(String),
    path: String,
    query: Option(String),
    fragment: Option(String),
  )
}

// Relative references are resolved with the RFC 3986 section 5.2 algorithm,
// which Turtle and TriG require. gleam/uri is not used because its JavaScript
// parser reads a relative path such as `c/d` as scheme `c` and path `/d`, and
// its Erlang parser lowercases the scheme, so the two targets disagreed.
fn parse_iri_reference(value: String) -> IriReference {
  let #(rest, fragment) = case string.split_once(value, "#") {
    Ok(#(before, after)) -> #(before, Some(after))
    Error(_) -> #(value, None)
  }
  let #(rest, query) = case string.split_once(rest, "?") {
    Ok(#(before, after)) -> #(before, Some(after))
    Error(_) -> #(rest, None)
  }
  let #(scheme, rest) = case string.split_once(rest, ":") {
    Ok(#(candidate, after)) ->
      case is_valid_scheme(candidate) {
        True -> #(Some(candidate), after)
        False -> #(None, rest)
      }
    Error(_) -> #(None, rest)
  }
  let #(authority, path) = case rest {
    "//" <> after ->
      case string.split_once(after, "/") {
        Ok(#(auth, path)) -> #(Some(auth), "/" <> path)
        Error(_) -> #(Some(after), "")
      }
    _ -> #(None, rest)
  }
  IriReference(scheme:, authority:, path:, query:, fragment:)
}

fn is_valid_scheme(candidate: String) -> Bool {
  case string.to_graphemes(candidate) {
    [first, ..rest] ->
      is_ascii_letter(first)
      && list.all(rest, fn(char) {
        is_ascii_letter(char)
        || is_ascii_digit(char)
        || char == "+"
        || char == "-"
        || char == "."
      })
    [] -> False
  }
}

fn is_ascii_letter(char: String) -> Bool {
  string.contains("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ", char)
  && string.length(char) == 1
}

fn is_ascii_digit(char: String) -> Bool {
  string.contains("0123456789", char) && string.length(char) == 1
}

fn resolve_reference(base: IriReference, ref: IriReference) -> IriReference {
  case ref.authority, ref.path {
    Some(_), _ ->
      IriReference(
        ..ref,
        scheme: base.scheme,
        path: remove_dot_segments(ref.path),
      )
    None, "" ->
      IriReference(
        ..base,
        query: option.or(ref.query, base.query),
        fragment: ref.fragment,
      )
    None, "/" <> _ ->
      IriReference(
        ..base,
        path: remove_dot_segments(ref.path),
        query: ref.query,
        fragment: ref.fragment,
      )
    None, _ ->
      IriReference(
        ..base,
        path: remove_dot_segments(merge_paths(base, ref.path)),
        query: ref.query,
        fragment: ref.fragment,
      )
  }
}

fn merge_paths(base: IriReference, ref_path: String) -> String {
  case base.authority, base.path {
    Some(_), "" -> "/" <> ref_path
    _, _ ->
      case string.split(base.path, "/") |> list.reverse {
        [_last, ..directories] ->
          string.join(list.reverse(["", ..directories]), "/") <> ref_path
        [] -> ref_path
      }
  }
}

fn remove_dot_segments(path: String) -> String {
  remove_dot_segments_loop(path, [])
}

fn remove_dot_segments_loop(input: String, output: List(String)) -> String {
  case input {
    "" -> string.concat(list.reverse(output))
    "../" <> rest | "./" <> rest -> remove_dot_segments_loop(rest, output)
    "/./" <> rest -> remove_dot_segments_loop("/" <> rest, output)
    "/." -> remove_dot_segments_loop("/", output)
    "/../" <> rest ->
      remove_dot_segments_loop("/" <> rest, drop_segment(output))
    "/.." -> remove_dot_segments_loop("/", drop_segment(output))
    "." | ".." -> remove_dot_segments_loop("", output)
    "/" <> rest ->
      case string.split_once(rest, "/") {
        Ok(#(segment, tail)) ->
          remove_dot_segments_loop("/" <> tail, ["/" <> segment, ..output])
        Error(_) -> remove_dot_segments_loop("", ["/" <> rest, ..output])
      }
    _ ->
      case string.split_once(input, "/") {
        Ok(#(segment, tail)) ->
          remove_dot_segments_loop("/" <> tail, [segment, ..output])
        Error(_) -> remove_dot_segments_loop("", [input, ..output])
      }
  }
}

fn drop_segment(output: List(String)) -> List(String) {
  case output {
    [_, ..rest] -> rest
    [] -> []
  }
}

fn recompose_iri(ref: IriReference) -> String {
  let scheme = case ref.scheme {
    Some(scheme) -> scheme <> ":"
    None -> ""
  }
  let authority = case ref.authority {
    Some(authority) -> "//" <> authority
    None -> ""
  }
  let query = case ref.query {
    Some(query) -> "?" <> query
    None -> ""
  }
  let fragment = case ref.fragment {
    Some(fragment) -> "#" <> fragment
    None -> ""
  }
  scheme <> authority <> ref.path <> query <> fragment
}

fn serialize_document(document: TurtleDocument) -> String {
  // A label that is not a valid PN_PREFIX could not be read back, so such
  // prefixes are neither declared nor used.
  let document =
    TurtleDocument(
      ..document,
      prefixes: dict.filter(document.prefixes, fn(name, _) {
        turtle_names.is_valid_prefix(name)
      }),
    )
  let base_lines = case document.base {
    Some(base) -> ["@base <" <> rdf_syntax.escape_iri(base) <> "> ."]
    None -> []
  }
  let prefix_lines =
    turtle_names.sorted_prefixes(document.prefixes)
    |> list.map(fn(pair) {
      let #(name, iri) = pair
      "@prefix " <> name <> ": <" <> rdf_syntax.escape_iri(iri) <> "> ."
    })
  let triple_lines =
    graph.triples(document.graph)
    |> list.map(fn(triple) { serialize_triple(triple, document.prefixes) })
  let all_lines =
    list.append(list.append(base_lines, prefix_lines), triple_lines)
  string.join(all_lines, "\n")
}

fn serialize_triple(
  triple: statement.Triple,
  prefixes: dict.Dict(String, String),
) -> String {
  let subject = serialize_subject(triple.subject, prefixes)
  let predicate = serialize_predicate(triple.predicate, prefixes)
  let object = serialize_object(triple.object, prefixes)
  subject <> " " <> predicate <> " " <> object <> " ."
}

fn serialize_subject(
  subject: term.Subject,
  prefixes: dict.Dict(String, String),
) -> String {
  case subject {
    term.SubjectNamed(node) -> serialize_named_node(node, prefixes)
    term.SubjectBlank(node) -> {
      let term.BlankNode(identifier) = node
      "_:" <> identifier
    }
    term.SubjectTriple(triple) -> serialize_triple_term(triple, prefixes)
  }
}

fn serialize_predicate(
  predicate: term.Predicate,
  prefixes: dict.Dict(String, String),
) -> String {
  let term.NamedNode(value) = predicate
  case value == rdf_type {
    True -> "a"
    False -> serialize_named_node(predicate, prefixes)
  }
}

fn serialize_object(
  object: term.Object,
  prefixes: dict.Dict(String, String),
) -> String {
  case object {
    term.ObjectNamed(node) -> serialize_named_node(node, prefixes)
    term.ObjectBlank(node) -> {
      let term.BlankNode(identifier) = node
      "_:" <> identifier
    }
    term.ObjectLiteral(literal) -> serialize_literal(literal, prefixes)
    term.ObjectTriple(triple) -> serialize_triple_term(triple, prefixes)
  }
}

fn serialize_triple_term(
  triple_term: term.TripleTerm,
  prefixes: dict.Dict(String, String),
) -> String {
  let term.TripleTerm(subject, predicate, object) = triple_term
  let subj_str = serialize_subject(subject, prefixes)
  let pred_str = serialize_predicate(predicate, prefixes)
  let obj_str = serialize_object(object, prefixes)
  "<<( " <> subj_str <> " " <> pred_str <> " " <> obj_str <> " )>>"
}

fn serialize_named_node(
  node: term.NamedNode,
  prefixes: dict.Dict(String, String),
) -> String {
  let term.NamedNode(value) = node
  case turtle_names.compact_iri(value, prefixes) {
    Some(prefixed_name) -> prefixed_name
    None -> "<" <> rdf_syntax.escape_iri(value) <> ">"
  }
}

fn serialize_literal(
  literal: term.Literal,
  prefixes: dict.Dict(String, String),
) -> String {
  case literal {
    term.SimpleLiteral(value) -> "\"" <> rdf_syntax.escape_string(value) <> "\""
    term.LanguageTaggedLiteral(value, tag) -> {
      let term.LanguageTag(lang) = tag
      "\"" <> rdf_syntax.escape_string(value) <> "\"@" <> lang
    }
    term.DirectionalLanguageTaggedLiteral(value, term.LanguageTag(lang), dir) ->
      "\""
      <> rdf_syntax.escape_string(value)
      <> "\"@"
      <> lang
      <> "--"
      <> term.base_direction_to_string(dir)
    term.TypedLiteral(value, datatype) -> {
      let term.NamedNode(dt) = datatype
      case turtle_names.is_bare_literal(value, dt) {
        True -> value
        False -> {
          let dt_text = serialize_named_node(datatype, prefixes)
          "\"" <> rdf_syntax.escape_string(value) <> "\"^^" <> dt_text
        }
      }
    }
  }
}

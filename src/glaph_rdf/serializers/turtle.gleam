//// Public API ////////////////////////////////////////////////////////////////
//// Tokenizer /////////////////////////////////////////////////////////////////
//// Parser ////////////////////////////////////////////////////////////////////
//// Serialization /////////////////////////////////////////////////////////////

import glaph_rdf/graph
import glaph_rdf/statement
import glaph_rdf/term
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri

const rdf_type = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"

const xsd_integer = "http://www.w3.org/2001/XMLSchema#integer"

const xsd_decimal = "http://www.w3.org/2001/XMLSchema#decimal"

const xsd_double = "http://www.w3.org/2001/XMLSchema#double"

const xsd_boolean = "http://www.w3.org/2001/XMLSchema#boolean"

pub type TurtleDocument {
  TurtleDocument(
    base: Option(String),
    prefixes: dict.Dict(String, String),
    graph: graph.Graph,
  )
}

pub type TurtleError {
  TurtleError(message: String, position: Int)
}

type NumberKind {
  IntegerNumber
  DecimalNumber
  DoubleNumber
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

pub fn parse(text: String) -> Result(TurtleDocument, TurtleError) {
  tokenize(text)
  |> result.try(parse_tokens)
}

pub fn parse_graph(text: String) -> Result(graph.Graph, TurtleError) {
  parse(text)
  |> result.map(fn(doc) { doc.graph })
}

pub fn serialize(document: TurtleDocument) -> String {
  serialize_document(document)
}

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

fn tokenize(text: String) -> Result(List(Token), TurtleError) {
  tokenize_loop(LexerState(string.to_graphemes(text), 0), [])
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
        [".", ..rest] -> Ok(#(Token(Dot, pos), LexerState(rest, pos + 1)))
        [";", ..rest] -> Ok(#(Token(Semicolon, pos), LexerState(rest, pos + 1)))
        [",", ..rest] -> Ok(#(Token(Comma, pos), LexerState(rest, pos + 1)))
        ["^", ..rest] -> lex_hat(LexerState(rest, pos + 1), pos)
        ["<", ..] -> lex_iri(state)
        ["\"", ..] -> lex_string(state)
        [":", ..] -> lex_prefixed_empty(state)
        ["_", ..rest] -> lex_blank(LexerState(rest, pos + 1), pos)
        [char, ..] ->
          case is_number_start(char) {
            True -> lex_number(state)
            False ->
              case is_name_start(char) {
                True -> lex_name_or_prefixed(state)
                False -> Error(TurtleError("Unexpected character", pos))
              }
          }
      }
  }
}

fn lex_directive_or_lang(
  state: LexerState,
  pos: Int,
) -> Result(#(Token, LexerState), TurtleError) {
  case state {
    LexerState(chars, _) -> {
      let keyword = string.concat(list.take(chars, 6))
      case
        string.starts_with(keyword, "prefix"),
        string.starts_with(keyword, "base")
      {
        True, _ -> {
          let rest = list.drop(chars, 6)
          Ok(#(Token(PrefixDirective, pos), LexerState(rest, pos + 6)))
        }
        _, True -> {
          let rest = list.drop(chars, 4)
          Ok(#(Token(BaseDirective, pos), LexerState(rest, pos + 4)))
        }
        _, _ ->
          take_while(state, is_lang_char)
          |> result.try(fn(pair) {
            let #(tag, state) = pair
            case tag {
              "" -> Error(TurtleError("Expected language tag", pos))
              _ -> Ok(#(Token(LangTag(tag), pos - 1), state))
            }
          })
      }
    }
  }
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

fn lex_string(state: LexerState) -> Result(#(Token, LexerState), TurtleError) {
  let LexerState(_, pos) = state
  advance_char(state)
  |> result.try(fn(state2) {
    collect_string(state2, [])
    |> result.map(fn(pair) {
      let #(value, state3) = pair
      #(Token(StringLiteral(value), pos), state3)
    })
  })
}

fn collect_string(
  state: LexerState,
  acc: List(String),
) -> Result(#(String, LexerState), TurtleError) {
  case state {
    LexerState(chars, pos) ->
      case list.is_empty(chars) {
        True -> Error(TurtleError("Unterminated string", pos))
        False ->
          case chars {
            ["\"", ..rest] ->
              Ok(#(string.concat(list.reverse(acc)), LexerState(rest, pos + 1)))
            ["\\", ..rest] ->
              parse_escape(LexerState(rest, pos + 1))
              |> result.try(fn(pair) {
                let #(char, state) = pair
                collect_string(state, [char, ..acc])
              })
            ["\n", ..] ->
              Error(TurtleError("Line break not allowed in string", pos))
            [char, ..rest] ->
              collect_string(LexerState(rest, pos + 1), [char, ..acc])
            [] -> Error(TurtleError("Unterminated string", pos))
          }
      }
  }
}

fn parse_escape(state: LexerState) -> Result(#(String, LexerState), TurtleError) {
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
                "\"" -> Ok(#("\"", LexerState(rest, pos + 1)))
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
  |> result.try(fn(state2) {
    take_while(state2, is_name_char)
    |> result.try(fn(pair) {
      let #(local, state3) = pair
      #(Token(Prefixed("", local), pos), state3) |> Ok
    })
  })
}

fn lex_blank(
  state: LexerState,
  pos: Int,
) -> Result(#(Token, LexerState), TurtleError) {
  case state {
    LexerState(chars, _) ->
      case chars {
        [":", ..rest] ->
          take_while(LexerState(rest, pos + 2), is_name_char)
          |> result.try(fn(pair) {
            let #(label, state) = pair
            case label {
              "" -> Error(TurtleError("Expected blank node label", pos))
              _ -> #(Token(BlankLabel(label), pos - 1), state) |> Ok
            }
          })
        _ -> Error(TurtleError("Invalid blank node", pos))
      }
  }
}

fn lex_number(state: LexerState) -> Result(#(Token, LexerState), TurtleError) {
  let LexerState(_, pos) = state
  take_while(state, is_number_char)
  |> result.map(fn(pair) {
    let #(text, state2) = pair
    let kind = classify_number(text)
    #(Token(NumberLiteral(kind, text), pos), state2)
  })
}

fn lex_name_or_prefixed(
  state: LexerState,
) -> Result(#(Token, LexerState), TurtleError) {
  let LexerState(_, pos) = state
  take_while(state, is_name_char)
  |> result.try(fn(pair) {
    let #(name, state) = pair
    case state {
      LexerState(chars, next_pos) ->
        case chars {
          [":", ..rest] ->
            take_while(LexerState(rest, next_pos + 1), is_name_char)
            |> result.try(fn(pair2) {
              let #(local, state) = pair2
              case local {
                "" -> {
                  let allow_empty = case state {
                    LexerState(chars2, _) ->
                      case chars2 {
                        [] -> True
                        [char2, ..] -> is_whitespace_char(char2) || char2 == "<"
                      }
                  }
                  case allow_empty {
                    True -> #(Token(Prefixed(name, local), pos), state) |> Ok
                    False -> {
                      let LexerState(_, lp_pos) = state
                      Error(TurtleError("Expected local part", lp_pos))
                    }
                  }
                }
                _ -> #(Token(Prefixed(name, local), pos), state) |> Ok
              }
            })
          _ ->
            case string.lowercase(name) {
              "true" -> Ok(#(Token(BooleanLiteral(True), pos), state))
              "false" -> Ok(#(Token(BooleanLiteral(False), pos), state))
              _ -> Ok(#(Token(Word(name), pos), state))
            }
        }
    }
  })
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

fn classify_number(text: String) -> NumberKind {
  let lower = string.lowercase(text)
  case string.contains(lower, "e") {
    True -> DoubleNumber
    False ->
      case string.contains(lower, ".") {
        True -> DecimalNumber
        False -> IntegerNumber
      }
  }
}

fn is_number_char(char: String) -> Bool {
  string.contains("0123456789+-.eE", char)
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

fn is_lang_char(char: String) -> Bool {
  let lower = string.lowercase(char)
  string.contains("abcdefghijklmnopqrstuvwxyz", lower) || char == "-"
}

fn is_hex_digit(char: String) -> Bool {
  string.contains("0123456789abcdefABCDEF", char)
}

fn parse_tokens(tokens: List(Token)) -> Result(TurtleDocument, TurtleError) {
  parse_directives(ParserState(tokens), None, dict.new())
  |> result.try(fn(triple) {
    let #(base, prefixes, state) = triple
    parse_triples(state, base, prefixes, [])
    |> result.try(fn(pair2) {
      let #(triples, state2) = pair2
      let ParserState(rest) = state2
      case rest {
        [] ->
          Ok(TurtleDocument(
            base: base,
            prefixes: prefixes,
            graph: graph.from_list(list.reverse(triples)),
          ))
        [Token(_, pos), ..] ->
          Error(TurtleError("Unexpected tokens after triples", pos))
      }
    })
  })
}

fn parse_directives(
  state: ParserState,
  base: Option(String),
  prefixes: dict.Dict(String, String),
) -> Result(
  #(Option(String), dict.Dict(String, String), ParserState),
  TurtleError,
) {
  case peek(state) {
    None -> Ok(#(base, prefixes, state))
    Some(Token(PrefixDirective, _)) ->
      parse_prefix(pop(state))
      |> result.try(fn(pair) {
        let #(prefix, iri, state) = pair
        parse_directives(state, base, dict.insert(prefixes, prefix, iri))
      })
    Some(Token(BaseDirective, _)) ->
      parse_base(pop(state))
      |> result.try(fn(pair) {
        let #(iri, state) = pair
        parse_directives(state, Some(iri), prefixes)
      })
    _ -> Ok(#(base, prefixes, state))
  }
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
        Token(Prefixed(prefix, _), _) -> Ok(prefix)
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

fn parse_triples(
  state: ParserState,
  base: Option(String),
  prefixes: dict.Dict(String, String),
  acc: List(statement.Triple),
) -> Result(#(List(statement.Triple), ParserState), TurtleError) {
  case peek(state) {
    None -> Ok(#(acc, state))
    Some(Token(Dot, _)) -> Ok(#(acc, state))
    Some(Token(Semicolon, _)) -> Ok(#(acc, state))
    Some(_) ->
      parse_triple(state, base, prefixes)
      |> result.try(fn(pair) {
        let #(triples, state) = pair
        parse_triples(state, base, prefixes, list.append(triples, acc))
      })
  }
}

fn parse_triple(
  state: ParserState,
  base: Option(String),
  prefixes: dict.Dict(String, String),
) -> Result(#(List(statement.Triple), ParserState), TurtleError) {
  parse_subject(state, base, prefixes)
  |> result.try(fn(pair) {
    let #(subject, state) = pair
    parse_predicate_object_list(state, subject, base, prefixes, [])
    |> result.try(fn(pair2) {
      let #(triples, state) = pair2
      consume_dot(state)
      |> result.map(fn(state) { #(triples, state) })
    })
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
            Some(Token(Dot, _)) | Some(Token(Semicolon, _)) | None ->
              Ok(#(combined, state))
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

// duplicate parse_object removed

fn parse_post_string(
  value: String,
  state: ParserState,
  base: Option(String),
  prefixes: dict.Dict(String, String),
  pos: Int,
) -> Result(#(term.Object, ParserState), TurtleError) {
  case consume_if(state, LangTag("")) {
    // The dummy value above is never matched; handled below with peek
    _ ->
      case peek(state) {
        Some(Token(LangTag(tag), _)) -> {
          let state = drop_one(state)
          term.language_tag(tag)
          |> result.map_error(fn(_) { TurtleError("Invalid language tag", pos) })
          |> result.map(fn(lang) {
            #(
              term.ObjectLiteral(term.LanguageTaggedLiteral(value, lang)),
              state,
            )
          })
        }
        Some(Token(HatHat, _)) -> {
          let state = drop_one(state)
          consume_token(state, fn(token) {
            case token {
              Token(IriRef(iri), pos2) ->
                apply_base(iri, base, pos2)
                |> result.try(fn(resolved) {
                  term.named_node(resolved)
                  |> result.map_error(fn(_) {
                    TurtleError("Invalid datatype", pos2)
                  })
                  |> result.map(fn(node) {
                    term.ObjectLiteral(term.TypedLiteral(value, node))
                  })
                })
              Token(Prefixed(prefix, local), pos2) ->
                resolve_prefixed(prefixes, prefix, local, pos2)
                |> result.try(fn(iri) {
                  term.named_node(iri)
                  |> result.map_error(fn(_) {
                    TurtleError("Invalid datatype", pos2)
                  })
                  |> result.map(fn(node) {
                    term.ObjectLiteral(term.TypedLiteral(value, node))
                  })
                })
              _ ->
                Error(TurtleError(
                  "Expected datatype IRI",
                  token_position(token),
                ))
            }
          })
          |> result.map(fn(pair) { pair })
        }
        _ -> Ok(#(term.ObjectLiteral(term.SimpleLiteral(value)), state))
      }
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
      Token(StringLiteral(value), pos) ->
        parse_post_string(value, state_after, base, prefixes, pos)
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
    LangTag(_) ->
      case expected {
        LangTag(_) -> True
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
    Some(base_iri) ->
      case string.contains(iri, ":") {
        True -> Ok(iri)
        False ->
          case uri.parse(base_iri) {
            Ok(base_uri) ->
              case uri.parse(iri) {
                Ok(relative) ->
                  case uri.merge(base_uri, relative) {
                    Ok(merged) -> Ok(uri.to_string(merged))
                    Error(_) -> Ok(base_iri <> iri)
                  }
                Error(_) -> Ok(base_iri <> iri)
              }
            Error(_) -> Ok(base_iri <> iri)
          }
      }
  }
}

fn serialize_document(document: TurtleDocument) -> String {
  let base_lines = case document.base {
    Some(base) -> ["@base <" <> escape_iri(base) <> "> ."]
    None -> []
  }
  let prefix_lines =
    dict.to_list(document.prefixes)
    |> list.map(fn(pair) {
      let #(name, iri) = pair
      "@prefix " <> name <> ": <" <> escape_iri(iri) <> "> ."
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
  }
}

fn serialize_named_node(
  node: term.NamedNode,
  prefixes: dict.Dict(String, String),
) -> String {
  let term.NamedNode(value) = node
  case find_prefix(value, prefixes) {
    Some(#(name, local)) ->
      case name == "" {
        True -> ":" <> local
        False -> name <> ":" <> local
      }
    None -> "<" <> escape_iri(value) <> ">"
  }
}

fn serialize_literal(
  literal: term.Literal,
  prefixes: dict.Dict(String, String),
) -> String {
  case literal {
    term.SimpleLiteral(value) -> "\"" <> escape_string(value) <> "\""
    term.LanguageTaggedLiteral(value, tag) -> {
      let term.LanguageTag(lang) = tag
      "\"" <> escape_string(value) <> "\"@" <> lang
    }
    term.TypedLiteral(value, datatype) -> {
      let term.NamedNode(dt) = datatype
      case
        dt == xsd_integer || dt == xsd_decimal || dt == xsd_double,
        dt == xsd_boolean
      {
        True, _ -> value
        _, True -> value
        _, _ -> {
          let dt_text = serialize_named_node(datatype, prefixes)
          "\"" <> escape_string(value) <> "\"^^" <> dt_text
        }
      }
    }
  }
}

fn escape_string(value: String) -> String {
  string.to_graphemes(value)
  |> list.map(fn(char) {
    case char {
      "\\" -> "\\\\"
      "\"" -> "\\\""
      "\n" -> "\\n"
      "\r" -> "\\r"
      "\t" -> "\\t"
      _ -> char
    }
  })
  |> string.concat
}

fn escape_iri(value: String) -> String {
  string.to_graphemes(value)
  |> list.map(fn(char) {
    case char {
      "\\" -> "\\\\"
      ">" -> "\\>"
      _ -> char
    }
  })
  |> string.concat
}

fn find_prefix(
  iri: String,
  prefixes: dict.Dict(String, String),
) -> Option(#(String, String)) {
  let best =
    dict.to_list(prefixes)
    |> list.fold(None, fn(current, entry) {
      let #(name, ns) = entry
      case string.starts_with(iri, ns) {
        True -> {
          let local = string.drop_start(iri, string.length(ns))
          case current {
            None -> Some(#(name, local, string.length(ns)))
            Some(#(best_name, best_local, best_len)) ->
              case string.length(ns) > best_len {
                True -> Some(#(name, local, string.length(ns)))
                False -> Some(#(best_name, best_local, best_len))
              }
          }
        }
        False -> current
      }
    })
  case best {
    Some(#(name, local, _)) -> Some(#(name, local))
    None -> None
  }
}

fn is_whitespace_char(char: String) -> Bool {
  case char {
    " " -> True
    "\t" -> True
    "\n" -> True
    "\r" -> True
    _ -> False
  }
}

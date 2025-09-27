//// Public API ////////////////////////////////////////////////////////////////
//// Serialization /////////////////////////////////////////////////////////////
//// Helper Functions //////////////////////////////////////////////////////////

import glaph_rdf/dataset
import glaph_rdf/graph
import glaph_rdf/statement
import glaph_rdf/term
import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

// Import the turtle module for parsing and reuse
import glaph_rdf/serializers/turtle

pub type TrigError {
  TrigError(message: String, position: Int)
}

pub type TrigDocument {
  TrigDocument(
    base: Option(String),
    prefixes: dict.Dict(String, String),
    dataset: dataset.Dataset,
  )
}

pub fn parse(text: String) -> Result(TrigDocument, TrigError) {
  // Simple TriG parser - for now, handle basic cases
  // TODO: Implement full TriG grammar with named graphs

  // Check if this looks like TriG (has GRAPH or {...} blocks)
  case string.contains(text, "GRAPH ") || string.contains(text, " {") {
    True -> parse_trig_format(text)
    False -> {
      // Parse as turtle and convert to TriG document
      case turtle.parse(text) {
        Ok(turtle_doc) -> {
          let dataset_with_default =
            dataset.new()
            |> dataset.replace_graph(term.DefaultGraph, turtle_doc.graph)

          Ok(TrigDocument(
            base: turtle_doc.base,
            prefixes: turtle_doc.prefixes,
            dataset: dataset_with_default,
          ))
        }
        Error(turtle.TurtleError(message, position)) ->
          Error(TrigError(message, position))
      }
    }
  }
}

fn parse_trig_format(_text: String) -> Result(TrigDocument, TrigError) {
  // For now, return empty TriG document - this needs full implementation
  // TODO: Implement proper TriG parser with GRAPH blocks
  Ok(TrigDocument(base: None, prefixes: dict.new(), dataset: dataset.new()))
}

pub fn parse_dataset(text: String) -> Result(dataset.Dataset, TrigError) {
  parse(text)
  |> result.map(fn(doc) { doc.dataset })
}

pub fn serialize(document: TrigDocument) -> String {
  serialize_document(document)
}

pub fn serialize_dataset(
  dataset_value: dataset.Dataset,
  base: Option(String),
  prefixes: dict.Dict(String, String),
) -> String {
  serialize_document(TrigDocument(
    base: base,
    prefixes: prefixes,
    dataset: dataset_value,
  ))
}

fn serialize_document(document: TrigDocument) -> String {
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

  // Serialize default graph triples (if any)
  let default_graph = dataset.default_graph(document.dataset)
  let default_triples = case graph.size(default_graph) {
    0 -> []
    _ ->
      graph.triples(default_graph)
      |> list.map(fn(triple) { serialize_triple(triple, document.prefixes) })
  }

  // Serialize named graphs
  let named_graph_lines =
    dataset.graph_names(document.dataset)
    |> list.map(fn(graph_name) {
      serialize_named_graph(graph_name, document.dataset, document.prefixes)
    })

  let all_lines =
    list.append(
      list.append(list.append(base_lines, prefix_lines), default_triples),
      named_graph_lines,
    )

  string.join(all_lines, "\n")
}

fn serialize_named_graph(
  graph_name: term.GraphName,
  dataset_value: dataset.Dataset,
  prefixes: dict.Dict(String, String),
) -> String {
  let graph_content = dataset.graph(dataset_value, graph_name)
  let triples = graph.triples(graph_content)

  let graph_label = case graph_name {
    term.DefaultGraph -> ""
    // This shouldn't happen for named graphs
    term.NamedGraph(node) -> serialize_named_node(node, prefixes)
    term.BlankGraph(node) -> {
      let term.BlankNode(identifier) = node
      "_:" <> identifier
    }
  }

  case list.is_empty(triples) {
    True -> graph_label <> " { }"
    False -> {
      let triple_lines =
        triples
        |> list.map(fn(triple) { "    " <> serialize_triple(triple, prefixes) })

      let graph_block = [
        graph_label <> " {",
        ..list.append(triple_lines, ["}"])
      ]

      string.join(graph_block, "\n")
    }
  }
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
  case value == "http://www.w3.org/1999/02/22-rdf-syntax-ns#type" {
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
        dt == "http://www.w3.org/2001/XMLSchema#integer"
        || dt == "http://www.w3.org/2001/XMLSchema#decimal"
        || dt == "http://www.w3.org/2001/XMLSchema#double",
        dt == "http://www.w3.org/2001/XMLSchema#boolean"
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

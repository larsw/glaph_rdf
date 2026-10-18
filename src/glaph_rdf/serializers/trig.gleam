//// Public API ////////////////////////////////////////////////////////////////
//// Serialization /////////////////////////////////////////////////////////////
//// Helper Functions //////////////////////////////////////////////////////////

import glaph_rdf/dataset
import glaph_rdf/graph
import glaph_rdf/internal/rdf_syntax
import glaph_rdf/internal/turtle_names
import glaph_rdf/internal/utf8
import glaph_rdf/statement
import glaph_rdf/term
import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile

// Import the turtle module for parsing and reuse
import glaph_rdf/serializers/turtle

/// Error information from TriG parsing operations.
///
/// Contains detailed error information including a descriptive message
/// and the character position where the error occurred in the input text.
/// This enables precise error reporting for debugging TriG syntax issues.
///
/// ## Examples
/// ```gleam
/// TrigError(
///   message: "Unexpected token 'GRAPH' at position 15", 
///   position: 15
/// )
/// ```
pub type TrigError {
  TrigError(message: String, position: Int)
}

/// A complete TriG document with base IRI, prefixes, and RDF dataset.
///
/// Represents a parsed or serializable TriG document containing all components:
/// optional base IRI for resolving relative references, namespace prefixes for
/// abbreviated IRIs, and the RDF dataset with multiple named graphs. TriG extends
/// Turtle to support datasets with named graphs using `GRAPH` blocks and RDF-star.
///
/// ## Examples
/// ```gleam
/// TrigDocument(
///   base: Some("http://example.org/"),
///   prefixes: dict.from_list([("ex", "http://example.org/"), ("foaf", "http://xmlns.com/foaf/0.1/")]),
///   dataset: my_rdf_dataset_with_named_graphs
/// )
/// ```
pub type TrigDocument {
  TrigDocument(
    base: Option(String),
    prefixes: dict.Dict(String, String),
    dataset: dataset.Dataset,
  )
}

/// Parse a TriG document from text into a structured representation.
///
/// Parses the Turtle statements the Turtle parser supports plus TriG graph
/// blocks: `{ ... }` (default graph), `label { ... }` and
/// `GRAPH label { ... }`, where the label is an IRI, prefixed name or blank
/// node. Directives may appear between blocks. RDF 1.2 triple terms
/// (`<<( s p o )>>`) and directional language-tagged strings (`"x"@en--ltr`)
/// are supported in every graph. Returns detailed error information on parse
/// failures.
///
/// ## Examples
/// ```gleam
/// let trig_text = "@prefix ex: <http://example.org/> .
///                  
///                  ex:graph1 {
///                    ex:alice ex:name \"Alice\" .
///                  }
///                  
///                  GRAPH ex:graph2 {
///                    ex:bob ex:age 25 .
///                  }"
/// 
/// case trig.parse(trig_text) {
///   Ok(document) -> {
///     // Access document.base, document.prefixes, document.dataset
///   }
///   Error(trig.TrigError(message, position)) -> {
///     // Handle parsing error with specific position
///   }
/// }
/// ```
pub fn parse(text: String) -> Result(TrigDocument, TrigError) {
  // The Turtle parser with graph blocks enabled. It skips one leading byte
  // order mark, so it is not stripped here as well.
  case turtle.parse_trig(text) {
    Ok(#(base, prefixes, quads)) ->
      Ok(TrigDocument(
        base: base,
        prefixes: prefixes,
        dataset: dataset.from_list(quads),
      ))
    Error(turtle.TurtleError(message, position)) ->
      Error(TrigError(message, position))
  }
}

/// Parse a TriG document and extract only the RDF dataset content.
///
/// Convenience function that parses TriG text and returns just the RDF dataset,
/// discarding base IRI and prefix declarations. Useful when you only need the
/// actual RDF data with its named graph structure without document metadata.
///
/// ## Examples
/// ```gleam
/// let trig_text = "@prefix ex: <http://example.org/> .
///                  
///                  ex:graph1 {
///                    ex:alice ex:name \"Alice\" .
///                  }"
/// 
/// case trig.parse_dataset(trig_text) {
///   Ok(rdf_dataset) -> {
///     let graph_names = dataset.graph_names(rdf_dataset)
///     // Work with the RDF dataset and named graphs directly
///   }
///   Error(error) -> // Handle parsing error
/// }
/// ```
pub fn parse_dataset(text: String) -> Result(dataset.Dataset, TrigError) {
  parse(text)
  |> result.map(fn(doc) { doc.dataset })
}

/// Serialize a TrigDocument to TriG format text.
///
/// Converts a structured TriG document back to valid TriG syntax text with
/// named graph blocks. Handles base declarations, prefix definitions, named
/// graphs using `GRAPH` statements or `{}` blocks, and RDF-star quoted triple
/// serialization. Output follows W3C TriG specification and is well-formatted.
///
/// ## Examples
/// ```gleam
/// let trig_text = trig.serialize(my_document)
/// 
/// // Result might look like:
/// // @base <http://example.org/> .
/// // @prefix ex: <http://example.org/> .
/// // 
/// // <http://example.org/graph1> {
/// //   ex:alice ex:name "Alice" .
/// // }
/// //
/// // GRAPH ex:graph2 {
/// //   ex:bob ex:age 25 .
/// // }
/// ```
pub fn serialize(document: TrigDocument) -> String {
  serialize_document(document)
}

/// Serialize an RDF dataset to TriG format with custom base and prefixes.
///
/// Convenience function that creates a TrigDocument from the provided components
/// and serializes it to TriG text with named graph support. Allows direct
/// serialization of RDF datasets with multiple named graphs, custom base IRI,
/// and prefix definitions without manually constructing a TrigDocument.
///
/// ## Examples
/// ```gleam
/// let prefixes = dict.from_list([
///   ("ex", "http://example.org/"),
///   ("foaf", "http://xmlns.com/foaf/0.1/")
/// ])
/// 
/// let trig_text = trig.serialize_dataset(
///   my_rdf_dataset,
///   Some("http://example.org/"),
///   prefixes
/// )
/// 
/// // Handles both default graph and named graphs automatically
/// ```
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

/// Parse a TriG document from a file into a structured representation.
///
/// Reads a TriG file and parses its contents including base declarations, 
/// prefix definitions, and named graph blocks. Falls back to Turtle parsing 
/// if no TriG-specific syntax is detected. Supports RDF-star quoted triples
/// within all graphs. Returns detailed error information on file read failures 
/// or parse errors.
///
/// ## Examples
/// ```gleam
/// case trig.parse_file("data/dataset.trig") {
///   Ok(document) -> {
///     // Access document.base, document.prefixes, document.dataset
///     let graph_names = dataset.graph_names(document.dataset)
///   }
///   Error(error) -> {
///     // Handle file read or parsing error
///   }
/// }
/// ```
pub fn parse_file(path: String) -> Result(TrigDocument, TrigError) {
  case utf8.read_file(path) {
    Ok(contents) -> parse(contents)
    Error(error) -> {
      let error_msg = case error {
        simplifile.Enoent -> "File not found"
        simplifile.Eacces -> "Permission denied"
        simplifile.Eisdir -> "Path is a directory"
        _ -> "File read error"
      }
      Error(TrigError("File error: " <> error_msg <> " (" <> path <> ")", 0))
    }
  }
}

/// Parse a TriG file and extract only the RDF dataset content.
///
/// Convenience function that reads and parses a TriG file, returning just 
/// the RDF dataset while discarding base IRI and prefix declarations. Useful 
/// when you only need the actual RDF data with its named graph structure
/// from the file.
///
/// ## Examples
/// ```gleam
/// case trig.parse_dataset_file("data/graphs.trig") {
///   Ok(rdf_dataset) -> {
///     let graph_names = dataset.graph_names(rdf_dataset)
///     // Work with the RDF dataset and named graphs directly
///   }
///   Error(error) -> // Handle file or parsing error
/// }
/// ```
pub fn parse_dataset_file(path: String) -> Result(dataset.Dataset, TrigError) {
  parse_file(path)
  |> result.map(fn(doc) { doc.dataset })
}

/// Serialize a TrigDocument to a file in TriG format.
///
/// Converts a structured TriG document to valid TriG syntax and writes it 
/// to the specified file with named graph blocks. Creates parent directories 
/// if they don't exist. Handles base declarations, prefix definitions, named 
/// graphs, and RDF-star quoted triple serialization.
///
/// ## Examples
/// ```gleam
/// let document = TrigDocument(
///   base: Some("http://example.org/"),
///   prefixes: my_prefixes,
///   dataset: my_dataset
/// )
/// 
/// case trig.serialize_to_file(document, "output/dataset.trig") {
///   Ok(Nil) -> // File written successfully
///   Error(error) -> // Handle file write error
/// }
/// ```
pub fn serialize_to_file(
  document: TrigDocument,
  path: String,
) -> Result(Nil, TrigError) {
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
      Error(TrigError("File error: " <> error_msg <> " (" <> path <> ")", 0))
    }
  }
}

/// Serialize an RDF dataset to a TriG file with custom base and prefixes.
///
/// Convenience function that creates a TrigDocument from the provided 
/// components and writes it to the specified file in TriG format with 
/// named graph support. Allows direct file output of RDF datasets with 
/// multiple named graphs, custom base IRI, and prefix definitions without 
/// manually constructing a TrigDocument.
///
/// ## Examples
/// ```gleam
/// let prefixes = dict.from_list([
///   ("ex", "http://example.org/"),
///   ("foaf", "http://xmlns.com/foaf/0.1/")
/// ])
/// 
/// case trig.serialize_dataset_to_file(
///   my_rdf_dataset,
///   Some("http://example.org/"),
///   prefixes,
///   "output/dataset.trig"
/// ) {
///   Ok(Nil) -> // Dataset written to file successfully
///   Error(error) -> // Handle file write error
/// }
/// ```
pub fn serialize_dataset_to_file(
  dataset_value: dataset.Dataset,
  base: Option(String),
  prefixes: dict.Dict(String, String),
  path: String,
) -> Result(Nil, TrigError) {
  serialize_to_file(
    TrigDocument(base: base, prefixes: prefixes, dataset: dataset_value),
    path,
  )
}

fn serialize_document(document: TrigDocument) -> String {
  // A label that is not a valid PN_PREFIX could not be read back, so such
  // prefixes are neither declared nor used.
  let document =
    TrigDocument(
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
    term.SubjectTriple(triple) -> serialize_triple_term(triple, prefixes)
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

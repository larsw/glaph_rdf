import glaph_rdf/dataset as dataset_mod
import glaph_rdf/graph as graph_mod
import glaph_rdf/statement as statement_mod
import glaph_rdf/term as term_mod
import gleam/uri.{type Uri}

/// The `glaph_rdf` module exposes a serialization-agnostic RDF 1.2 data model.
///
/// It provides:
/// - Validated RDF terms including IRIs, blank nodes, and canonicalised
///   BCP&nbsp;47 language tags.
/// - Triple, quad, graph, and dataset collections with set-like behaviour.
/// - Helpers to move between human-friendly IRIs and `gleam/uri.Uri` values by
///   automatically percent-encoding or decoding non-ASCII code points.
///
/// Typical projects use this module exclusively, while the underlying
/// implementation details live in `glaph_rdf/term`, `glaph_rdf/statement`,
/// `glaph_rdf/graph`, and `glaph_rdf/dataset`.
pub type TermError =
  term_mod.TermError

pub type NamedNode =
  term_mod.NamedNode

pub type BlankNode =
  term_mod.BlankNode

pub type LanguageTag =
  term_mod.LanguageTag

pub type BaseDirection =
  term_mod.BaseDirection

pub type Literal =
  term_mod.Literal

pub type Term =
  term_mod.Term

pub type Subject =
  term_mod.Subject

pub type Predicate =
  term_mod.Predicate

pub type Object =
  term_mod.Object

pub type GraphName =
  term_mod.GraphName

pub type Triple =
  statement_mod.Triple

pub type Quad =
  statement_mod.Quad

pub type Graph =
  graph_mod.Graph

pub type Dataset =
  dataset_mod.Dataset

/// Create a `NamedNode` from an absolute IRI, validating it against
/// RFC&nbsp;3987 syntax and RDF 1.2 constraints.
pub fn named_node(value: String) -> Result(NamedNode, TermError) {
  term_mod.named_node(value)
}

/// Create a blank node identifier using the RDF grammar for blank labels.
pub fn blank_node(identifier: String) -> Result(BlankNode, TermError) {
  term_mod.blank_node(identifier)
}

/// Parse and canonicalise a BCP&nbsp;47 language tag.
///
/// The returned value is normalised (e.g. script title case, region uppercase)
/// and grandfathered tags are preserved.
pub fn language_tag(value: String) -> Result(LanguageTag, TermError) {
  term_mod.language_tag(value)
}

/// Parse an IRI string into a `gleam/uri.Uri`, percent-encoding non-ASCII
/// code points as required by RFC&nbsp;3986.
pub fn iri_to_uri(value: String) -> Result(Uri, TermError) {
  term_mod.iri_to_uri(value)
}

/// Decode a `gleam/uri.Uri` back into an IRI string by expanding percent-encoded
/// non-ASCII code points.
pub fn uri_to_iri(uri_value: Uri) -> Result(String, TermError) {
  term_mod.uri_to_iri(uri_value)
}

/// Convert a `NamedNode` into a parsed `gleam/uri.Uri` value.
pub fn named_node_to_uri(node: NamedNode) -> Result(Uri, TermError) {
  term_mod.named_node_to_uri(node)
}

/// Build a validated `NamedNode` from a previously parsed `gleam/uri.Uri`.
pub fn named_node_from_uri(uri_value: Uri) -> Result(NamedNode, TermError) {
  term_mod.named_node_from_uri(uri_value)
}

/// Decode percent-encoded sequences in an IRI where the bytes correspond to
/// non-ASCII Unicode code points. ASCII sequences remain untouched.
pub fn decode_iri(value: String) -> Result(String, TermError) {
  term_mod.decode_iri(value)
}

/// Construct an RDF literal without a language or datatype.
pub fn simple_literal(value: String) -> Literal {
  term_mod.simple_literal(value)
}

/// Construct a literal tagged with a canonicalised language tag.
pub fn language_literal(value: String, tag: LanguageTag) -> Literal {
  term_mod.language_literal(value, tag)
}

/// Parse an RDF 1.2 base direction: exactly `ltr` or `rtl` (lowercase, as
/// RDF 1.2 Concepts requires).
///
/// ## Examples
/// ```gleam
/// base_direction("rtl")
/// // -> Ok(term.RightToLeft)
/// base_direction("up")
/// // -> Error(term.InvalidBaseDirection("up"))
/// ```
pub fn base_direction(value: String) -> Result(BaseDirection, TermError) {
  term_mod.base_direction(value)
}

/// Construct an RDF 1.2 directional language-tagged literal
/// (`"value"@tag--ltr`, datatype `rdf:dirLangString`).
///
/// ## Examples
/// ```gleam
/// let assert Ok(tag) = language_tag("ar")
/// let assert Ok(direction) = base_direction("rtl")
/// directional_language_literal("مرحبا", tag, direction)
/// // -> term.DirectionalLanguageTaggedLiteral("مرحبا", tag, term.RightToLeft)
/// ```
pub fn directional_language_literal(
  value: String,
  tag: LanguageTag,
  direction: BaseDirection,
) -> Literal {
  term_mod.directional_language_literal(value, tag, direction)
}

/// Construct a typed literal given an RDF datatype IRI.
///
/// The datatype must not be `rdf:langString` or `rdf:dirLangString`: such a
/// literal has no language tag, so it is not well-formed RDF, and the parsers
/// reject what the writers print for it. Use `language_literal` or
/// `directional_language_literal` for language-tagged strings.
///
/// ## Examples
/// ```gleam
/// let assert Ok(datatype) =
///   named_node("http://www.w3.org/2001/XMLSchema#integer")
/// typed_literal("42", datatype)
/// // -> term.TypedLiteral("42", datatype)
/// ```
pub fn typed_literal(value: String, datatype: NamedNode) -> Literal {
  term_mod.typed_literal(value, datatype)
}

/// Attempt to view a generic `Term` as an RDF subject.
pub fn subject_from_term(term: Term) -> Result(Subject, TermError) {
  term_mod.subject_from_term(term)
}

/// Convert a generic `Term` into an RDF object.
pub fn object_from_term(term: Term) -> Object {
  term_mod.object_from_term(term)
}

/// Attempt to view a generic `Term` as a graph name.
pub fn graph_name_from_term(term: Term) -> Result(GraphName, TermError) {
  term_mod.graph_name_from_term(term)
}

/// Build an RDF triple from a subject, predicate, and object.
pub fn triple(
  subject: Subject,
  predicate: Predicate,
  object: Object,
) -> Triple {
  statement_mod.triple(subject, predicate, object)
}

/// Build a triple directly from generic `Term` values.
pub fn triple_from_terms(
  subject: Term,
  predicate: NamedNode,
  object: Term,
) -> Result(Triple, TermError) {
  statement_mod.triple_from_terms(subject, predicate, object)
}

/// Extend a triple with a graph name to produce an RDF quad.
pub fn quad(triple: Triple, graph: GraphName) -> Quad {
  statement_mod.quad(triple, graph)
}

/// Build a quad directly from generic `Term` values.
pub fn quad_from_terms(
  subject: Term,
  predicate: NamedNode,
  object: Term,
  graph: GraphName,
) -> Result(Quad, TermError) {
  statement_mod.quad_from_terms(subject, predicate, object, graph)
}

/// Create an empty RDF graph.
pub fn new_graph() -> Graph {
  graph_mod.new()
}

/// Construct a graph from an initial list of triples (duplicates removed).
pub fn graph_from_list(triples: List(Triple)) -> Graph {
  graph_mod.from_list(triples)
}

/// Return all triples stored in the graph.
pub fn graph_triples(graph: Graph) -> List(Triple) {
  graph_mod.triples(graph)
}

/// Return the number of distinct triples in the graph.
pub fn graph_size(graph: Graph) -> Int {
  graph_mod.size(graph)
}

/// Insert a triple if it is not already present.
pub fn graph_add(graph: Graph, triple: Triple) -> Graph {
  graph_mod.add(graph, triple)
}

/// Test whether a triple is already part of the graph.
pub fn graph_contains(graph: Graph, triple: Triple) -> Bool {
  graph_mod.contains(graph, triple)
}

/// Remove a triple from the graph.
pub fn graph_remove(graph: Graph, triple: Triple) -> Graph {
  graph_mod.remove(graph, triple)
}

/// Merge two graphs, keeping a set of unique triples.
pub fn graph_merge(into graph: Graph, from other: Graph) -> Graph {
  graph_mod.merge(graph, other)
}

/// Create an empty RDF dataset.
pub fn new_dataset() -> Dataset {
  dataset_mod.new()
}

/// Construct a dataset from an initial list of quads (duplicates removed).
pub fn dataset_from_list(quads: List(Quad)) -> Dataset {
  dataset_mod.from_list(quads)
}

/// Return all quads stored in the dataset.
pub fn dataset_quads(dataset: Dataset) -> List(Quad) {
  dataset_mod.quads(dataset)
}

/// Return the number of quads stored in the dataset.
pub fn dataset_quad_count(dataset: Dataset) -> Int {
  dataset_mod.quad_count(dataset)
}

/// Insert a quad if it is not already present.
pub fn dataset_add_quad(dataset: Dataset, quad: Quad) -> Dataset {
  dataset_mod.add_quad(dataset, quad)
}

/// Insert a triple into the dataset's default graph.
pub fn dataset_add_triple(dataset: Dataset, triple: Triple) -> Dataset {
  dataset_mod.add_triple(dataset, triple)
}

/// Test whether a quad is stored within the dataset.
pub fn dataset_contains_quad(dataset: Dataset, quad: Quad) -> Bool {
  dataset_mod.contains_quad(dataset, quad)
}

/// Test whether a triple exists in a target graph.
pub fn dataset_contains_triple(
  dataset: Dataset,
  triple: Triple,
  graph_name: GraphName,
) -> Bool {
  dataset_mod.contains_triple(dataset, triple, graph_name)
}

/// Remove a quad from the dataset.
pub fn dataset_remove_quad(dataset: Dataset, quad: Quad) -> Dataset {
  dataset_mod.remove_quad(dataset, quad)
}

/// Remove every quad that belongs to a named graph.
pub fn dataset_remove_graph(dataset: Dataset, name: GraphName) -> Dataset {
  dataset_mod.remove_graph(dataset, name)
}

/// Extract the default graph from the dataset.
pub fn dataset_default_graph(dataset: Dataset) -> Graph {
  dataset_mod.default_graph(dataset)
}

/// Extract a named graph from the dataset.
pub fn dataset_graph(dataset: Dataset, name: GraphName) -> Graph {
  dataset_mod.graph(dataset, name)
}

/// Merge two datasets, keeping a set of unique quads.
pub fn dataset_merge(into dataset: Dataset, from other: Dataset) -> Dataset {
  dataset_mod.merge(dataset, other)
}

/// Replace an entire named graph with a new graph of triples.
pub fn dataset_replace_graph(
  dataset: Dataset,
  name: GraphName,
  new_graph: Graph,
) -> Dataset {
  dataset_mod.replace_graph(dataset, name, new_graph)
}

/// List all named graphs contained within the dataset (excluding the default
/// graph).
pub fn dataset_graph_names(dataset: Dataset) -> List(GraphName) {
  dataset_mod.graph_names(dataset)
}

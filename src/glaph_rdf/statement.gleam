import glaph_rdf/term
import gleam/result

/// An RDF triple (statement) containing subject, predicate, and object.
///
/// A triple is the fundamental unit of RDF data, representing a single
/// statement about a resource. It follows the pattern "subject predicate object"
/// where the subject is what the statement is about, the predicate is the
/// property or relationship, and the object is the value or related resource.
///
/// ## Examples
/// ```gleam
/// Triple(
///   subject: SubjectNamed(NamedNode("http://example.org/alice")),
///   predicate: NamedNode("http://xmlns.com/foaf/0.1/name"), 
///   object: ObjectLiteral(SimpleLiteral("Alice"))
/// )
/// // Represents: <http://example.org/alice> foaf:name "Alice" .
/// ```
pub type Triple {
  Triple(subject: term.Subject, predicate: term.Predicate, object: term.Object)
}

/// An RDF quad (triple with graph context) for use in RDF datasets.
///
/// A quad extends a triple by adding graph context, allowing the same
/// triple to exist in multiple named graphs within a dataset. This is
/// essential for representing provenance, versioning, or organizing
/// data from multiple sources.
///
/// ## Examples
/// ```gleam
/// Quad(
///   subject: SubjectNamed(NamedNode("http://example.org/alice")),
///   predicate: NamedNode("http://xmlns.com/foaf/0.1/name"),
///   object: ObjectLiteral(SimpleLiteral("Alice")),
///   graph: NamedGraph(NamedNode("http://example.org/graph1"))
/// )
/// // Represents: <http://example.org/graph1> { <alice> foaf:name "Alice" . }
/// ```
pub type Quad {
  Quad(
    subject: term.Subject,
    predicate: term.Predicate,
    object: term.Object,
    graph: term.GraphName,
  )
}

/// Create an RDF triple from validated terms.
///
/// Constructs a triple from the provided subject, predicate, and object terms.
/// All terms should already be validated and of the correct types for their
/// positions in the triple.
///
/// ## Examples
/// ```gleam
/// let my_triple = statement.triple(
///   term.SubjectNamed(alice_node),
///   name_predicate,
///   term.ObjectLiteral(name_literal)
/// )
/// ```
pub fn triple(
  subject: term.Subject,
  predicate: term.Predicate,
  object: term.Object,
) -> Triple {
  Triple(subject: subject, predicate: predicate, object: object)
}

/// Create an RDF triple from general terms with validation.
///
/// Constructs a triple from general Term types, validating that the subject
/// term can be used in subject position (no literals allowed). The predicate
/// must be a NamedNode, and any term type can be used as object.
///
/// ## Examples
/// ```gleam
/// statement.triple_from_terms(
///   term.NamedTerm(alice_node),    // Valid subject
///   name_predicate,                // Must be NamedNode
///   term.LiteralTerm(name_literal) // Any term type allowed
/// )
/// // -> Ok(Triple(...))
/// 
/// statement.triple_from_terms(
///   term.LiteralTerm(literal),     // Invalid subject
///   predicate,
///   object
/// )
/// // -> Error(InvalidSubjectTerm)
/// ```
pub fn triple_from_terms(
  subject: term.Term,
  predicate: term.NamedNode,
  object: term.Term,
) -> Result(Triple, term.TermError) {
  term.subject_from_term(subject)
  |> result.map(fn(subj) {
    Triple(
      subject: subj,
      predicate: predicate,
      object: term.object_from_term(object),
    )
  })
}

/// Create an RDF quad by adding graph context to a triple.
///
/// Constructs a quad by combining an existing triple with a graph name.
/// This is useful when adding triples to specific named graphs in a dataset.
///
/// ## Examples
/// ```gleam
/// let my_quad = statement.quad(
///   existing_triple, 
///   term.NamedGraph(graph_iri)
/// )
/// 
/// // Add to default graph
/// let default_quad = statement.quad(
///   triple,
///   term.DefaultGraph
/// )
/// ```
pub fn quad(triple: Triple, graph: term.GraphName) -> Quad {
  Quad(
    subject: triple.subject,
    predicate: triple.predicate,
    object: triple.object,
    graph: graph,
  )
}

/// Create an RDF quad from general terms with validation.
///
/// Constructs a quad by first creating and validating a triple from the
/// provided terms, then adding the graph context. This combines the
/// validation logic of `triple_from_terms` with graph assignment.
///
/// ## Examples
/// ```gleam
/// statement.quad_from_terms(
///   term.NamedTerm(alice_node),
///   name_predicate,
///   term.LiteralTerm(name_literal),
///   term.NamedGraph(graph_iri)
/// )
/// // -> Ok(Quad(...))
/// ```
pub fn quad_from_terms(
  subject: term.Term,
  predicate: term.NamedNode,
  object: term.Term,
  graph: term.GraphName,
) -> Result(Quad, term.TermError) {
  triple_from_terms(subject, predicate, object)
  |> result.map(fn(triple) { quad(triple, graph) })
}

/// Create an RDF quad from an existing triple and graph name.
///
/// This is an alias for the `quad()` function, providing clearer intent
/// when converting existing triples to quads for dataset operations.
///
/// ## Examples
/// ```gleam
/// let my_quad = statement.quad_from_triple(
///   existing_triple,
///   term.NamedGraph(graph_iri)
/// )
/// ```
pub fn quad_from_triple(triple: Triple, graph: term.GraphName) -> Quad {
  quad(triple, graph)
}

/// Extract the triple portion from an RDF quad.
///
/// Returns a triple by removing the graph context from a quad. This is
/// useful when you need to work with the statement content independent
/// of its graph context.
///
/// ## Examples
/// ```gleam
/// let just_triple = statement.triple_from_quad(my_quad)
/// 
/// // Extract triples from all quads in a list
/// let triples = list.map(quads, statement.triple_from_quad)
/// ```
pub fn triple_from_quad(q: Quad) -> Triple {
  Triple(subject: q.subject, predicate: q.predicate, object: q.object)
}

/// Change the graph context of an existing quad.
///
/// Creates a new quad with the same triple content but different graph
/// context. This is useful for moving statements between graphs or
/// changing the provenance context of existing data.
///
/// ## Examples
/// ```gleam
/// let moved_quad = statement.with_graph(
///   original_quad,
///   term.NamedGraph(new_graph_iri)
/// )
/// 
/// // Move to default graph
/// let default_quad = statement.with_graph(
///   named_graph_quad,
///   term.DefaultGraph
/// )
/// ```
pub fn with_graph(q: Quad, graph: term.GraphName) -> Quad {
  Quad(
    subject: q.subject,
    predicate: q.predicate,
    object: q.object,
    graph: graph,
  )
}

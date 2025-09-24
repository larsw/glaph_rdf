import gleam/result
import glaph_rdf/term

pub type Triple {
  Triple(subject: term.Subject, predicate: term.Predicate, object: term.Object)
}

pub type Quad {
  Quad(
    subject: term.Subject,
    predicate: term.Predicate,
    object: term.Object,
    graph: term.GraphName,
  )
}

pub fn triple(subject: term.Subject, predicate: term.Predicate, object: term.Object) -> Triple {
  Triple(subject: subject, predicate: predicate, object: object)
}

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

pub fn quad(triple: Triple, graph: term.GraphName) -> Quad {
  Quad(
    subject: triple.subject,
    predicate: triple.predicate,
    object: triple.object,
    graph: graph,
  )
}

pub fn quad_from_terms(
  subject: term.Term,
  predicate: term.NamedNode,
  object: term.Term,
  graph: term.GraphName,
) -> Result(Quad, term.TermError) {
  triple_from_terms(subject, predicate, object)
  |> result.map(fn(triple) { quad(triple, graph) })
}

pub fn quad_from_triple(triple: Triple, graph: term.GraphName) -> Quad {
  quad(triple, graph)
}

pub fn triple_from_quad(q: Quad) -> Triple {
  Triple(subject: q.subject, predicate: q.predicate, object: q.object)
}

pub fn with_graph(q: Quad, graph: term.GraphName) -> Quad {
  Quad(
    subject: q.subject,
    predicate: q.predicate,
    object: q.object,
    graph: graph,
  )
}

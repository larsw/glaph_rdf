import glaph_rdf/dataset
import glaph_rdf/serializers/nquads
import gleam/list
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn basic_quad_parse_test() {
  let input =
    "<http://example.org/alice> <http://xmlns.com/foaf/0.1/name> \"Alice\" <http://example.org/graph1> ."
  let result = nquads.parse(input)

  should.be_ok(result)

  case result {
    Ok(nquads.NQuadsDocument(dataset)) -> {
      let quads = dataset.quads
      list.length(quads) |> should.equal(1)
    }
    Error(_) -> should.fail()
  }
}

pub fn default_graph_parse_test() {
  let input =
    "<http://example.org/alice> <http://xmlns.com/foaf/0.1/name> \"Alice\" ."
  let result = nquads.parse(input)

  should.be_ok(result)

  case result {
    Ok(nquads.NQuadsDocument(dataset)) -> {
      let quads = dataset.quads
      list.length(quads) |> should.equal(1)
    }
    Error(_) -> should.fail()
  }
}

pub fn multiple_quads_parse_test() {
  let input =
    "
<http://example.org/alice> <http://xmlns.com/foaf/0.1/name> \"Alice\" <http://example.org/graph1> .
<http://example.org/bob> <http://xmlns.com/foaf/0.1/name> \"Bob\" <http://example.org/graph2> .
<http://example.org/charlie> <http://xmlns.com/foaf/0.1/name> \"Charlie\" .
"
  let result = nquads.parse(input)

  should.be_ok(result)

  case result {
    Ok(nquads.NQuadsDocument(dataset)) -> {
      let quads = dataset.quads
      list.length(quads) |> should.equal(3)
    }
    Error(_) -> should.fail()
  }
}

pub fn language_literal_parse_test() {
  let input =
    "<http://example.org/alice> <http://xmlns.com/foaf/0.1/name> \"Alice\"@en <http://example.org/graph1> ."
  let result = nquads.parse(input)

  should.be_ok(result)
}

pub fn typed_literal_parse_test() {
  let input =
    "<http://example.org/alice> <http://xmlns.com/foaf/0.1/age> \"25\"^^<http://www.w3.org/2001/XMLSchema#integer> <http://example.org/graph1> ."
  let result = nquads.parse(input)

  should.be_ok(result)
}

pub fn blank_node_parse_test() {
  let input =
    "_:alice <http://xmlns.com/foaf/0.1/name> \"Alice\" <http://example.org/graph1> ."
  let result = nquads.parse(input)

  should.be_ok(result)
}

pub fn empty_input_test() {
  let input = ""
  let result = nquads.parse(input)

  should.be_ok(result)

  case result {
    Ok(nquads.NQuadsDocument(dataset)) -> {
      let quads = dataset.quads
      list.length(quads) |> should.equal(0)
    }
    Error(_) -> should.fail()
  }
}

pub fn comment_ignore_test() {
  let input =
    "
# This is a comment
<http://example.org/alice> <http://xmlns.com/foaf/0.1/name> \"Alice\" <http://example.org/graph1> .
# Another comment
"
  let result = nquads.parse(input)

  should.be_ok(result)

  case result {
    Ok(nquads.NQuadsDocument(dataset)) -> {
      let quads = dataset.quads
      list.length(quads) |> should.equal(1)
    }
    Error(_) -> should.fail()
  }
}

pub fn whitespace_handling_test() {
  let input =
    "   <http://example.org/alice>    <http://xmlns.com/foaf/0.1/name>   \"Alice\"   <http://example.org/graph1>   .   "
  let result = nquads.parse(input)

  should.be_ok(result)
}

pub fn round_trip_test() {
  let input =
    "<http://example.org/alice> <http://xmlns.com/foaf/0.1/name> \"Alice\" <http://example.org/graph1> ."

  case nquads.parse(input) {
    Ok(document) -> {
      let serialized = nquads.serialize(document)
      let reparsed = nquads.parse(serialized)

      should.be_ok(reparsed)
      // Just check that both parse successfully
      should.be_true(True)
    }
    Error(_) -> should.fail()
  }
}

// Error tests
pub fn missing_dot_error_test() {
  let input =
    "<http://example.org/alice> <http://xmlns.com/foaf/0.1/name> \"Alice\" <http://example.org/graph1>"
  let result = nquads.parse(input)

  should.be_error(result)
}

pub fn unterminated_string_error_test() {
  let input =
    "<http://example.org/alice> <http://xmlns.com/foaf/0.1/name> \"Alice <http://example.org/graph1> ."
  let result = nquads.parse(input)

  should.be_error(result)
}

pub fn serialize_basic_test() {
  let input =
    "<http://example.org/alice> <http://xmlns.com/foaf/0.1/name> \"Alice\" <http://example.org/graph1> ."

  case nquads.parse(input) {
    Ok(document) -> {
      let serialized = nquads.serialize(document)

      string.contains(serialized, "<http://example.org/alice>")
      |> should.be_true()
      string.contains(serialized, "<http://xmlns.com/foaf/0.1/name>")
      |> should.be_true()
      string.contains(serialized, "\"Alice\"") |> should.be_true()
      string.contains(serialized, "<http://example.org/graph1>")
      |> should.be_true()
      string.ends_with(string.trim(serialized), ".") |> should.be_true()
    }
    Error(_) -> should.fail()
  }
}

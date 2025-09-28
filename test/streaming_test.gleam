import glaph_rdf/graph
import glaph_rdf/serializers/ntriples
import glaph_rdf/statement
import glaph_rdf/term
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import gleeunit
import gleeunit/should
import simplifile

pub fn main() {
  gleeunit.main()
}

pub fn streaming_ntriples_parse_test() {
  // Create a large test file
  let filename = "test_large.nt"
  let test_content = create_large_ntriples_content(1000)

  // Write the test file
  should.be_ok(simplifile.write(filename, test_content))

  // Test streaming parse
  case ntriples.streaming_parse_file(filename) {
    Ok(document) -> {
      io.println(
        "Streaming parsed "
        <> int.to_string(graph.size(document.graph))
        <> " triples",
      )
      graph.size(document.graph) |> should.equal(1000)
    }
    Error(_err) -> {
      should.fail()
    }
  }

  // Clean up
  let _ = simplifile.delete(filename)
}

pub fn streaming_ntriples_serialize_test() {
  // Create a large graph
  let large_graph = create_large_graph(500)
  let filename = "test_output.nt"

  // Test streaming serialize
  case ntriples.streaming_serialize_to_file(large_graph, filename) {
    Ok(_) -> {
      io.println(
        "Successfully streamed "
        <> int.to_string(graph.size(large_graph))
        <> " triples to file",
      )

      // Verify the file was created and has content
      case simplifile.read(filename) {
        Ok(content) -> {
          // Count lines (each triple is one line)
          let line_count =
            content
            |> string.split(on: "\n")
            |> list.filter(keeping: fn(line) { string.trim(line) != "" })
            |> list.length

          line_count |> should.equal(500)
        }
        Error(_) -> should.fail()
      }
    }
    Error(_err) -> {
      should.fail()
    }
  }

  // Clean up
  let _ = simplifile.delete(filename)
}

fn create_large_ntriples_content(count: Int) -> String {
  create_ntriples_lines(count, 1, "")
}

fn create_ntriples_lines(remaining: Int, current: Int, acc: String) -> String {
  case remaining {
    0 -> acc
    _ -> {
      let line =
        "<http://example.org/subject"
        <> int.to_string(current)
        <> "> <http://example.org/predicate> \"Object "
        <> int.to_string(current)
        <> "\" .\n"
      create_ntriples_lines(remaining - 1, current + 1, acc <> line)
    }
  }
}

fn create_large_graph(count: Int) -> graph.Graph {
  create_graph_triples(count, 1, graph.new())
}

fn create_graph_triples(
  remaining: Int,
  current: Int,
  acc_graph: graph.Graph,
) -> graph.Graph {
  case remaining {
    0 -> acc_graph
    _ -> {
      let subject =
        term.SubjectNamed(term.NamedNode(
          "http://example.org/subject" <> int.to_string(current),
        ))
      let predicate = term.NamedNode("http://example.org/predicate")
      let object =
        term.ObjectLiteral(term.SimpleLiteral(
          "Object " <> int.to_string(current),
        ))
      let triple =
        statement.Triple(subject: subject, predicate: predicate, object: object)

      let updated_graph = graph.add(acc_graph, triple)
      create_graph_triples(remaining - 1, current + 1, updated_graph)
    }
  }
}

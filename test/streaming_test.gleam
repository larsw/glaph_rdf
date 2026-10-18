import glaph_rdf/dataset
import glaph_rdf/graph
import glaph_rdf/internal/rdf_syntax
import glaph_rdf/serializers/nquads
import glaph_rdf/serializers/ntriples
import glaph_rdf/statement
import glaph_rdf/term
import gleam/float
import gleam/int
import gleam/list
import gleam/string
import gleeunit/should
import simplifile

// Helpers

/// A fresh path under `build/` (ignored by git). The random suffix keeps
/// concurrent runs (e.g. Erlang and JavaScript) from clashing. Tests delete
/// the file before asserting, so a failing assertion leaves nothing behind.
fn temp_path(name: String, extension: String) -> String {
  "build/tmp_streaming_"
  <> name
  <> "_"
  <> int.to_string(int.random(1_000_000_000))
  <> extension
}

/// Writes `content` to a fresh temp file, runs `work` on its path and deletes
/// the file again before returning `work`'s result.
fn with_file(
  name: String,
  extension: String,
  content: BitArray,
  work: fn(String) -> a,
) -> a {
  let path = temp_path(name, extension)
  let assert Ok(Nil) = simplifile.write_bits(path, content)
  let result = work(path)
  let _ = simplifile.delete(path)
  result
}

fn with_text_file(
  name: String,
  extension: String,
  content: String,
  work: fn(String) -> a,
) -> a {
  with_file(name, extension, <<content:utf8>>, work)
}

/// Runs `work` with a fresh path that it may write to; deletes it afterwards.
fn with_output_path(
  name: String,
  extension: String,
  work: fn(String) -> a,
) -> a {
  let path = temp_path(name, extension)
  let result = work(path)
  let _ = simplifile.delete(path)
  result
}

/// The integers from `from` to `to`, inclusive.
fn ints(from: Int, to: Int) -> List(Int) {
  ints_loop(to, from, [])
}

fn ints_loop(current: Int, from: Int, acc: List(Int)) -> List(Int) {
  case current < from {
    True -> acc
    False -> ints_loop(current - 1, from, [current, ..acc])
  }
}

fn named(iri: String) -> term.NamedNode {
  term.NamedNode(iri)
}

fn subject_triple(i: Int) -> statement.Triple {
  statement.Triple(
    subject: term.SubjectNamed(named(
      "http://example.org/subject" <> int.to_string(i),
    )),
    predicate: named("http://example.org/predicate"),
    object: term.ObjectLiteral(term.SimpleLiteral("Object " <> int.to_string(i))),
  )
}

fn ntriples_lines(count: Int) -> String {
  ints(1, count)
  |> list.map(fn(i) {
    "<http://example.org/subject"
    <> int.to_string(i)
    <> "> <http://example.org/predicate> \"Object "
    <> int.to_string(i)
    <> "\" .\n"
  })
  |> string.concat
}

// Timing (to catch quadratic graph building)
//
// Parsing speed depends on the machine, so the graph-building parsers are
// timed relative to a baseline that parses the same lines but builds
// nothing: `streaming_fold_file` for `streaming_parse_file`, and splitting
// plus `rdf_syntax.parse_statement` for `parse`. Building the graph with the
// O(n log n) bulk constructor adds little; the old O(n^2) `graph.add` fold
// made parsing 20_000 lines four to ten times slower than the baseline.

@target(erlang)
@external(erlang, "erlang", "monotonic_time")
fn erlang_monotonic_time(unit: Int) -> Int

@target(javascript)
@external(javascript, "node:process", "uptime")
fn uptime_seconds() -> Float

@target(erlang)
fn now_ms() -> Float {
  int.to_float(erlang_monotonic_time(1000))
}

@target(javascript)
fn now_ms() -> Float {
  uptime_seconds() *. 1000.0
}

/// Runs `work` and returns its result with the elapsed milliseconds.
fn timed(work: fn() -> a) -> #(a, Float) {
  let start = now_ms()
  let result = work()
  #(result, now_ms() -. start)
}

/// Fails if `elapsed` is more than `factor` times `baseline` plus one
/// second, which leaves room for garbage collection and a busy machine.
fn assert_not_much_slower(
  label: String,
  elapsed: Float,
  baseline: Float,
  factor: Float,
) {
  let budget = factor *. baseline +. 1000.0
  case elapsed <=. budget {
    True -> Nil
    False ->
      panic as {
        label
        <> " took "
        <> int.to_string(float.round(elapsed))
        <> "ms, budget is "
        <> int.to_string(float.round(budget))
        <> "ms (quadratic graph building?)"
      }
  }
}

// Shared fixtures

/// Covers duplicates, comments (full-line, indented, trailing), blank lines,
/// CRLF, non-ASCII, escapes, a literal with spaces and a language tag, typed
/// literals, blank nodes and triple terms.
const ntriples_fixture =
  "# leading comment\n"
  <> "<http://ex.org/s> <http://ex.org/p> \"plain with spaces\" .\r\n"
  <> "\n"
  <> "  # indented comment\n"
  <> "<http://ex.org/s> <http://ex.org/p> \"Grüße, 世界\"@de .\n"
  <> "_:b0 <http://ex.org/p> \"tab\\there \\\"quoted\\\" C:\\\\new\" . # trailing\n"
  <> "<http://ex.org/s> <http://ex.org/p> \"42\"^^<http://www.w3.org/2001/XMLSchema#integer> .\r\n"
  <> "<< <http://ex.org/a> <http://ex.org/b> \"x y\" >> <http://ex.org/says> <http://ex.org/c> .\n"
  <> "<http://ex.org/d> <http://ex.org/q> <<( _:b0 <http://ex.org/r> \"ü\" )>> .\n"
  <> "<http://ex.org/s> <http://ex.org/p> \"plain with spaces\" .\n"

const nquads_fixture =
  "# leading comment\n"
  <> "<http://ex.org/s> <http://ex.org/p> \"default with spaces\" .\r\n"
  <> "<http://ex.org/s> <http://ex.org/p> \"named \\\"one\\\"\\n\" <http://ex.org/g1> .\n"
  <> "\n"
  <> "  # indented comment\n"
  <> "_:b0 <http://ex.org/p> \"Grüße, 世界\"@de _:g2 . # trailing\n"
  <> "<http://ex.org/s> <http://ex.org/p> \"42\"^^<http://www.w3.org/2001/XMLSchema#integer> <http://ex.org/g1> .\r\n"
  <> "<<( <http://ex.org/a> <http://ex.org/b> \"x )>> y\" )>> <http://ex.org/says> <http://ex.org/c> .\n"
  <> "<http://ex.org/d> <http://ex.org/q> <<( _:b0 <http://ex.org/r> \"ü\" )>> <http://ex.org/g1> .\n"
  <> "<http://ex.org/s> <http://ex.org/p> \"default with spaces\" .\n"

// N-Triples streaming

pub fn streaming_ntriples_parse_test() {
  let parsed =
    with_text_file("nt_parse", ".nt", ntriples_lines(1000), fn(path) {
      #(ntriples.streaming_parse_file(path), ntriples.parse_file(path))
    })
  let assert #(Ok(streamed), Ok(loaded)) = parsed
  graph.size(streamed.graph) |> should.equal(1000)
  streamed |> should.equal(loaded)
}

pub fn streaming_ntriples_serialize_test() {
  let large_graph = graph.from_list(list.map(ints(1, 500), subject_triple))
  let #(written, content) =
    with_output_path("nt_serialize", ".nt", fn(path) {
      #(
        ntriples.streaming_serialize_to_file(large_graph, path),
        simplifile.read(path),
      )
    })
  written |> should.equal(Ok(Nil))
  content |> should.equal(Ok(ntriples.serialize_graph(large_graph)))
}

pub fn streaming_ntriples_matches_parse_file_test() {
  let #(streamed, loaded) =
    with_text_file("nt_fixture", ".nt", ntriples_fixture, fn(path) {
      #(ntriples.streaming_parse_file(path), ntriples.parse_file(path))
    })
  let assert Ok(document) = streamed
  // 7 statements, one of them a duplicate.
  graph.size(document.graph) |> should.equal(6)
  streamed |> should.equal(loaded)
  streamed |> should.equal(ntriples.parse(ntriples_fixture))
}

pub fn streaming_ntriples_round_trip_test() {
  let assert Ok(original) = ntriples.parse_graph(ntriples_fixture)
  let #(written, content, reparsed) =
    with_output_path("nt_round_trip", ".nt", fn(path) {
      let written = ntriples.streaming_serialize_to_file(original, path)
      #(written, simplifile.read(path), ntriples.streaming_parse_file(path))
    })
  written |> should.equal(Ok(Nil))
  content |> should.equal(Ok(ntriples.serialize_graph(original)))
  reparsed |> should.equal(Ok(ntriples.NTriplesDocument(graph: original)))
}

pub fn streaming_ntriples_parse_error_matches_parse_file_test() {
  let content =
    "<http://ex.org/s> <http://ex.org/p> \"ok\" .\n"
    <> "# comment\n"
    <> "<http://ex.org/s> <http://ex.org/p> \"no dot\"\n"
  let #(streamed, loaded) =
    with_text_file("nt_bad_line", ".nt", content, fn(path) {
      #(ntriples.streaming_parse_file(path), ntriples.parse_file(path))
    })
  let assert Error(ntriples.NTriplesError(message, line)) = streamed
  line |> should.equal(3)
  message |> should.equal("N-Triples statement must end with a dot (.)")
  streamed |> should.equal(loaded)
}

pub fn streaming_ntriples_missing_file_test() {
  let path = temp_path("nt_missing", ".nt")
  let assert Error(ntriples.NTriplesError(message, line)) =
    ntriples.streaming_parse_file(path)
  line |> should.equal(0)
  message
  |> should.equal("File error: No such file or directory (" <> path <> ")")
}

pub fn streaming_ntriples_invalid_utf8_reports_line_test() {
  let content = <<
    "<http://ex.org/s> <http://ex.org/p> \"ok\" .\n":utf8,
    "<http://ex.org/s> <http://ex.org/p> \"":utf8,
    0xFF,
    "\" .\n":utf8,
  >>
  let #(path, result) =
    with_file("nt_invalid_utf8", ".nt", content, fn(path) {
      #(path, ntriples.streaming_parse_file(path))
    })
  result
  |> should.equal(
    Error(ntriples.NTriplesError(
      "File error: Invalid UTF-8 (" <> path <> ")",
      2,
    )),
  )
}

pub fn streaming_ntriples_fold_file_test() {
  let #(count, collected) =
    with_text_file("nt_fold", ".nt", ntriples_fixture, fn(path) {
      #(
        ntriples.streaming_fold_file(path, from: 0, with: fn(n, _) { n + 1 }),
        ntriples.streaming_fold_file(path, from: [], with: fn(acc, triple) {
          [triple, ..acc]
        }),
      )
    })
  // Every statement is passed to the callback, duplicates included.
  count |> should.equal(Ok(7))
  let assert Ok(triples) = collected
  let assert Ok(parsed) = ntriples.parse_graph(ntriples_fixture)
  graph.from_list(list.reverse(triples)) |> should.equal(parsed)
}

pub fn streaming_ntriples_fold_file_error_test() {
  let content = "<http://ex.org/s> .\n"
  let result =
    with_text_file("nt_fold_error", ".nt", content, fn(path) {
      ntriples.streaming_fold_file(path, from: 0, with: fn(n, _) { n + 1 })
    })
  let assert Error(expected) = ntriples.parse(content)
  result |> should.equal(Error(expected))
}

pub fn streaming_ntriples_serialize_missing_directory_test() {
  let path = "build/tmp_streaming_missing_dir/sub/out.nt"
  let assert Error(ntriples.NTriplesError(message, line)) =
    ntriples.streaming_serialize_to_file(
      graph.from_list([subject_triple(1)]),
      path,
    )
  line |> should.equal(0)
  message |> string.starts_with("File error: ") |> should.be_true
  message |> string.ends_with(" (" <> path <> ")") |> should.be_true
}

/// `/dev/full` accepts the open but fails every write with ENOSPC. On
/// Erlang the write is buffered (delayed write) and the error only shows up
/// when the file is closed; on JavaScript the write itself fails. Either way
/// the error must be returned.
pub fn streaming_ntriples_serialize_full_disk_test() {
  case simplifile.file_info("/dev/full") {
    Error(_) -> Nil
    Ok(_) -> {
      let small_graph = graph.from_list(list.map(ints(1, 500), subject_triple))
      ntriples.streaming_serialize_to_file(small_graph, "/dev/full")
      |> should.equal(
        Error(ntriples.NTriplesError(
          "File error: No space left on device (/dev/full)",
          0,
        )),
      )
    }
  }
}

pub fn streaming_ntriples_large_file_is_not_quadratic_test() {
  let content = ntriples_lines(20_000)
  let #(folded, streamed, parsed) =
    with_text_file("nt_large", ".nt", content, fn(path) {
      #(
        timed(fn() {
          ntriples.streaming_fold_file(path, from: 0, with: fn(n, _) { n + 1 })
        }),
        timed(fn() { ntriples.streaming_parse_file(path) }),
        timed(fn() { ntriples.parse(content) }),
      )
    })
  let #(_, split_baseline) =
    timed(fn() {
      string.split(content, "\n")
      |> list.fold(0, fn(n, line) {
        case rdf_syntax.parse_statement(line, rdf_syntax.NTriples) {
          Ok(_) -> n + 1
          Error(_) -> n
        }
      })
    })
  let #(count, fold_baseline) = folded
  count |> should.equal(Ok(20_000))
  let #(streamed, streamed_ms) = streamed
  let #(parsed, parsed_ms) = parsed
  // Accumulating the statements costs the streaming parser some extra GC time,
  // so it gets a larger factor than `parse`, whose baseline holds the same
  // input in memory.
  assert_not_much_slower(
    "streaming_parse_file",
    streamed_ms,
    fold_baseline,
    3.0,
  )
  assert_not_much_slower("parse", parsed_ms, split_baseline, 2.0)
  let assert Ok(document) = streamed
  graph.size(document.graph) |> should.equal(20_000)
  streamed |> should.equal(parsed)
}

// N-Quads streaming

pub fn streaming_nquads_matches_parse_file_test() {
  let #(streamed, loaded) =
    with_text_file("nq_fixture", ".nq", nquads_fixture, fn(path) {
      #(nquads.streaming_parse_file(path), nquads.parse_file(path))
    })
  let assert Ok(document) = streamed
  // 7 statements, one of them a duplicate.
  dataset.quad_count(document.dataset) |> should.equal(6)
  streamed |> should.equal(loaded)
  streamed |> should.equal(nquads.parse(nquads_fixture))

  // Default graph, an IRI-named graph and a blank-node-named graph.
  graph.size(dataset.default_graph(document.dataset)) |> should.equal(2)
  graph.size(dataset.graph(
    document.dataset,
    term.NamedGraph(named("http://ex.org/g1")),
  ))
  |> should.equal(3)
  let assert True =
    list.contains(
      dataset.graph_names(document.dataset),
      term.BlankGraph(term.BlankNode("g2")),
    )
}

pub fn streaming_nquads_literal_escapes_test() {
  let content =
    "<http://ex.org/s> <http://ex.org/p> \"a b\\t\\\"c\\\" \\\\ d\" <http://ex.org/g> .\n"
  let streamed =
    with_text_file("nq_escapes", ".nq", content, fn(path) {
      nquads.streaming_parse_file(path)
    })
  let assert Ok(document) = streamed
  dataset.quads(document.dataset)
  |> should.equal([
    statement.Quad(
      subject: term.SubjectNamed(named("http://ex.org/s")),
      predicate: named("http://ex.org/p"),
      object: term.ObjectLiteral(term.SimpleLiteral("a b\t\"c\" \\ d")),
      graph: term.NamedGraph(named("http://ex.org/g")),
    ),
  ])
}

pub fn streaming_nquads_serialize_exact_bytes_test() {
  let assert Ok(original) = nquads.parse_dataset(nquads_fixture)
  let #(written, content, reparsed) =
    with_output_path("nq_round_trip", ".nq", fn(path) {
      let written = nquads.streaming_serialize_to_file(original, path)
      #(written, simplifile.read(path), nquads.streaming_parse_file(path))
    })
  written |> should.equal(Ok(Nil))
  content |> should.equal(Ok(nquads.serialize_dataset(original)))
  reparsed |> should.equal(Ok(nquads.NQuadsDocument(dataset: original)))
}

pub fn streaming_nquads_serialize_default_and_named_lines_test() {
  let quads = [
    statement.Quad(
      subject: term.SubjectNamed(named("http://ex.org/s")),
      predicate: named("http://ex.org/p"),
      object: term.ObjectLiteral(term.SimpleLiteral("in default")),
      graph: term.DefaultGraph,
    ),
    statement.Quad(
      subject: term.SubjectBlank(term.BlankNode("b")),
      predicate: named("http://ex.org/p"),
      object: term.ObjectNamed(named("http://ex.org/o")),
      graph: term.NamedGraph(named("http://ex.org/g")),
    ),
  ]
  let content =
    with_output_path("nq_lines", ".nq", fn(path) {
      let assert Ok(Nil) =
        nquads.streaming_serialize_to_file(dataset.from_list(quads), path)
      simplifile.read(path)
    })
  content
  |> should.equal(Ok(
    "<http://ex.org/s> <http://ex.org/p> \"in default\" .\n"
    <> "_:b <http://ex.org/p> <http://ex.org/o> <http://ex.org/g> .\n",
  ))
}

pub fn streaming_nquads_parse_error_matches_parse_file_test() {
  let content =
    "<http://ex.org/s> <http://ex.org/p> \"ok\" <http://ex.org/g> .\n"
    <> "\n"
    <> "<http://ex.org/s> <http://ex.org/p> \"o\" <http://ex.org/g> <http://ex.org/x> .\n"
  let #(streamed, loaded) =
    with_text_file("nq_bad_line", ".nq", content, fn(path) {
      #(nquads.streaming_parse_file(path), nquads.parse_file(path))
    })
  let assert Error(nquads.NQuadsError(_, 3)) = streamed
  streamed |> should.equal(loaded)
}

pub fn streaming_nquads_missing_file_test() {
  let path = temp_path("nq_missing", ".nq")
  nquads.streaming_parse_file(path)
  |> should.equal(
    Error(nquads.NQuadsError(
      "File error: No such file or directory (" <> path <> ")",
      0,
    )),
  )
}

pub fn streaming_nquads_invalid_utf8_reports_line_test() {
  let content = <<
    "# comment\n":utf8,
    "\n":utf8,
    "<http://ex.org/s> <http://ex.org/p> \"":utf8,
    0xC3,
    "\" .\n":utf8,
  >>
  let #(path, result) =
    with_file("nq_invalid_utf8", ".nq", content, fn(path) {
      #(path, nquads.streaming_parse_file(path))
    })
  result
  |> should.equal(
    Error(nquads.NQuadsError("File error: Invalid UTF-8 (" <> path <> ")", 3)),
  )
}

pub fn streaming_nquads_fold_file_test() {
  let #(named_count, collected) =
    with_text_file("nq_fold", ".nq", nquads_fixture, fn(path) {
      #(
        nquads.streaming_fold_file(path, from: 0, with: fn(n, quad) {
          case quad.graph {
            term.DefaultGraph -> n
            _ -> n + 1
          }
        }),
        nquads.streaming_fold_file(path, from: [], with: fn(acc, quad) {
          [quad, ..acc]
        }),
      )
    })
  named_count |> should.equal(Ok(4))
  let assert Ok(quads) = collected
  list.length(quads) |> should.equal(7)
  let assert Ok(parsed) = nquads.parse_dataset(nquads_fixture)
  dataset.from_list(list.reverse(quads)) |> should.equal(parsed)
}

pub fn streaming_nquads_serialize_full_disk_test() {
  case simplifile.file_info("/dev/full") {
    Error(_) -> Nil
    Ok(_) -> {
      let assert Ok(ds) = nquads.parse_dataset(nquads_fixture)
      nquads.streaming_serialize_to_file(ds, "/dev/full")
      |> should.equal(
        Error(nquads.NQuadsError(
          "File error: No space left on device (/dev/full)",
          0,
        )),
      )
    }
  }
}

pub fn streaming_nquads_large_file_is_not_quadratic_test() {
  let content =
    ints(1, 20_000)
    |> list.map(fn(i) {
      "<http://ex.org/s"
      <> int.to_string(i)
      <> "> <http://ex.org/p> \"o\" <http://ex.org/g"
      <> int.to_string(i % 7)
      <> "> .\n"
    })
    |> string.concat
  let #(folded, streamed, parsed) =
    with_text_file("nq_large", ".nq", content, fn(path) {
      #(
        timed(fn() {
          nquads.streaming_fold_file(path, from: 0, with: fn(n, _) { n + 1 })
        }),
        timed(fn() { nquads.streaming_parse_file(path) }),
        timed(fn() { nquads.parse(content) }),
      )
    })
  let #(_, split_baseline) =
    timed(fn() {
      string.split(content, "\n")
      |> list.fold(0, fn(n, line) {
        case rdf_syntax.parse_statement(line, rdf_syntax.NQuads) {
          Ok(_) -> n + 1
          Error(_) -> n
        }
      })
    })
  let #(count, fold_baseline) = folded
  count |> should.equal(Ok(20_000))
  let #(streamed, streamed_ms) = streamed
  let #(parsed, parsed_ms) = parsed
  // Accumulating the statements costs the streaming parser some extra GC time,
  // so it gets a larger factor than `parse`, whose baseline holds the same
  // input in memory.
  assert_not_much_slower(
    "streaming_parse_file",
    streamed_ms,
    fold_baseline,
    3.0,
  )
  assert_not_much_slower("parse", parsed_ms, split_baseline, 2.0)
  let assert Ok(document) = streamed
  dataset.quad_count(document.dataset) |> should.equal(20_000)
  streamed |> should.equal(parsed)
}

//// Regression tests for behaviour that used to differ between the Erlang and
//// JavaScript targets, or between `parse_file` and the streaming parsers:
////
//// - IRI validation relied on `gleam/uri.parse`, which rejects illegal
////   characters on Erlang only, so `named_node("http://exa mple.org")` was
////   accepted on JavaScript.
//// - On JavaScript, U+FEFF at the start of a line was silently dropped by
////   the streaming parsers (and a leading BOM by `parse_file`).
//// - CRLF files: `parse`/`parse_file` kept the CR in each line while the
////   streaming reader stripped it, so the same syntax error got different
////   messages.

import file_streams/file_stream
import glaph_rdf/graph
import glaph_rdf/internal/line_reader
import glaph_rdf/serializers/nquads
import glaph_rdf/serializers/ntriples
import glaph_rdf/serializers/trig
import glaph_rdf/serializers/turtle
import glaph_rdf/term
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should
import simplifile

// Helpers ---------------------------------------------------------------------

const bom = <<0xEF, 0xBB, 0xBF>>

/// Writes `content` to a fresh file under `build/`, runs `work` on its path
/// and deletes the file again.
fn with_file(name: String, content: BitArray, work: fn(String) -> a) -> a {
  let path =
    "build/tmp_portability_"
    <> name
    <> "_"
    <> int.to_string(int.random(1_000_000_000))
  let assert Ok(Nil) = simplifile.write_bits(path, content)
  let result = work(path)
  let _ = simplifile.delete(path)
  result
}

fn read_lines(name: String, content: BitArray, chunk_size: Int) {
  use path <- with_file(name, content)
  let assert Ok(stream) = file_stream.open_read(path)
  let lines =
    line_reader.new_with_chunk_size(stream, chunk_size)
    |> line_reader.fold_reader([], fn(acc, line, _number) { Ok([line, ..acc]) })
    |> result.map(list.reverse)
  let assert Ok(Nil) = file_stream.close(stream)
  lines
}

fn is_invalid_iri(value: String) -> Bool {
  term.named_node(value) == Error(term.InvalidIri(value))
}

// IRI validation --------------------------------------------------------------

pub fn iri_with_space_is_rejected_test() {
  is_invalid_iri("http://exa mple.org") |> should.be_true
  is_invalid_iri("http://ex.org/a b") |> should.be_true
  is_invalid_iri("http://ex.org/a?b c") |> should.be_true
  is_invalid_iri("http://ex.org/a#b c") |> should.be_true
  is_invalid_iri("urn:a b") |> should.be_true
  term.iri_to_uri("http://exa mple.org")
  |> should.equal(Error(term.InvalidIri("http://exa mple.org")))
}

pub fn iri_forbidden_characters_are_rejected_test() {
  let forbidden = ["<", ">", "\"", "{", "}", "|", "^", "`", "\\", "\u{7F}"]
  let controls = ["\u{00}", "\t", "\n", "\r", "\u{1F}"]
  list.each(list.append(forbidden, controls), fn(char) {
    is_invalid_iri("http://ex.org/a" <> char <> "b") |> should.be_true
    is_invalid_iri("http://ex" <> char <> "ample.org/") |> should.be_true
    is_invalid_iri("http://ex.org/?q=" <> char) |> should.be_true
    is_invalid_iri("urn:x" <> char) |> should.be_true
  })
}

pub fn iri_structure_is_checked_on_every_target_test() {
  // A fragment cannot contain `#`; brackets only enclose an IPv6 host; the
  // authority has at most one `@`.
  is_invalid_iri("http://ex.org/a#b#c") |> should.be_true
  is_invalid_iri("http://ex.org/[x]") |> should.be_true
  is_invalid_iri("http://ex.org/a?b[1]") |> should.be_true
  is_invalid_iri("urn:[x]") |> should.be_true
  is_invalid_iri("http://[bad/") |> should.be_true
  is_invalid_iri("http://[1.2.3.4]/") |> should.be_true
  is_invalid_iri("http://[1::2::3]/") |> should.be_true
  is_invalid_iri("http://[12345::]/") |> should.be_true
  is_invalid_iri("http://[v1.x]/") |> should.be_true
  is_invalid_iri("http://[::1]x/") |> should.be_true
  is_invalid_iri("http://u@ex@ex.org/") |> should.be_true
}

pub fn valid_iris_are_still_accepted_test() {
  [
    "http://example.org/a?b=c#d",
    "http://u:p@ex.org:8080/x",
    "http://[::1]/",
    "http://[::1]:80/a",
    "http://[fe80::1]/",
    "http://[::ffff:1.2.3.4]/",
    "http://u@[2001:db8::7]/",
    "http://ex.org/%E2%82%AC",
    "https://例え.テスト/パス?クエリ=値#フラグ",
    "urn:isbn:0451450523",
    "mailto:a@b.org",
  ]
  |> list.each(fn(iri) {
    term.named_node(iri) |> should.equal(Ok(term.NamedNode(iri)))
  })
}

pub fn ntriples_rejects_iri_with_space_escape_test() {
  // ` ` decodes to a space, which must be rejected on every target.
  let assert Error(_) =
    ntriples.parse("<http://ex.org/a\\u0020b> <http://ex.org/p> \"o\" .\n")
}

// Byte order marks ------------------------------------------------------------

pub fn line_reader_keeps_bom_after_first_line_test() {
  let content = <<"a\n":utf8, bom:bits, "b\n":utf8>>
  list.each([1, 2, 3, 65_536], fn(size) {
    read_lines("lr_bom_mid", content, size)
    |> should.equal(Ok(["a", "\u{FEFF}b"]))
  })
}

pub fn line_reader_strips_only_one_leading_bom_test() {
  list.each([1, 2, 65_536], fn(size) {
    read_lines("lr_bom_lead", <<bom:bits, "a\nb":utf8>>, size)
    |> should.equal(Ok(["a", "b"]))
    read_lines("lr_bom_twice", <<bom:bits, bom:bits, "a":utf8>>, size)
    |> should.equal(Ok(["\u{FEFF}a"]))
  })
}

pub fn bom_mid_file_is_rejected_by_streaming_and_parse_file_test() {
  let nt = <<
    "<http://ex.org/s> <http://ex.org/p> \"a\" .\n":utf8,
    bom:bits,
    "<http://ex.org/s> <http://ex.org/p> \"b\" .\n":utf8,
  >>
  let #(streamed, folded, loaded) =
    with_file("nt_bom_mid", nt, fn(path) {
      #(
        ntriples.streaming_parse_file(path),
        ntriples.streaming_fold_file(path, from: 0, with: fn(n, _) { n + 1 }),
        ntriples.parse_file(path),
      )
    })
  let assert Error(ntriples.NTriplesError(_, 2)) = streamed
  streamed |> should.equal(loaded)
  let assert Error(ntriples.NTriplesError(_, 2)) = folded

  let nq = <<
    "<http://ex.org/s> <http://ex.org/p> \"a\" <http://ex.org/g> .\n":utf8,
    bom:bits,
    "<http://ex.org/s> <http://ex.org/p> \"b\" .\n":utf8,
  >>
  let #(streamed, loaded) =
    with_file("nq_bom_mid", nq, fn(path) {
      #(nquads.streaming_parse_file(path), nquads.parse_file(path))
    })
  let assert Error(nquads.NQuadsError(_, 2)) = streamed
  streamed |> should.equal(loaded)
}

pub fn leading_bom_is_accepted_by_every_file_parser_test() {
  let statement = "<http://ex.org/s> <http://ex.org/p> \"o\" .\n"
  let content = <<bom:bits, statement:utf8>>
  let assert Ok(expected) = ntriples.parse(statement)

  let #(streamed, loaded, quads_streamed, quads_loaded, ttl, trig_doc) =
    with_file("all_bom_lead", content, fn(path) {
      #(
        ntriples.streaming_parse_file(path),
        ntriples.parse_file(path),
        nquads.streaming_parse_file(path),
        nquads.parse_file(path),
        turtle.parse_file(path),
        trig.parse_file(path),
      )
    })
  streamed |> should.equal(Ok(expected))
  loaded |> should.equal(Ok(expected))
  quads_streamed |> should.equal(quads_loaded)
  let assert Ok(_) = quads_loaded
  let assert Ok(turtle_document) = ttl
  turtle_document.graph |> should.equal(expected.graph)
  let assert Ok(_) = trig_doc
}

pub fn leading_bom_is_not_stripped_by_parse_test() {
  // `parse` takes text, not a file: a U+FEFF there is a syntax error.
  let assert Error(ntriples.NTriplesError(_, 1)) =
    ntriples.parse("\u{FEFF}<http://ex.org/s> <http://ex.org/p> \"o\" .\n")
}

// CRLF ------------------------------------------------------------------------

pub fn crlf_syntax_errors_match_between_streaming_and_parse_file_test() {
  let ok_line = "<http://e/s> <http://e/p> <http://e/o> .\r\n"
  let cases = [
    #(
      ok_line <> "<http://e/s> <http://e/p> \"abc\r\n",
      "Unterminated string literal",
    ),
    #(
      ok_line <> "<http://e/s> <http://e/p> <http://e/o\r\n",
      "Unterminated IRI: missing '>'",
    ),
    #(
      ok_line <> "<http://e/s> <http://e/p> <http://e/o>\r\n",
      "N-Triples statement must end with a dot (.)",
    ),
  ]
  list.each(cases, fn(test_case) {
    let #(content, message) = test_case
    let #(streamed, loaded, parsed) =
      with_file("nt_crlf_error", <<content:utf8>>, fn(path) {
        #(
          ntriples.streaming_parse_file(path),
          ntriples.parse_file(path),
          ntriples.parse(content),
        )
      })
    streamed |> should.equal(Error(ntriples.NTriplesError(message, 2)))
    loaded |> should.equal(streamed)
    parsed |> should.equal(streamed)

    let #(streamed, loaded) =
      with_file("nq_crlf_error", <<content:utf8>>, fn(path) {
        #(nquads.streaming_parse_file(path), nquads.parse_file(path))
      })
    let assert Error(nquads.NQuadsError(_, 2)) = streamed
    loaded |> should.equal(streamed)
  })
}

pub fn crlf_documents_parse_like_lf_documents_test() {
  let lf =
    "<http://e/s> <http://e/p> \"a\" .\n# comment\n<http://e/s> <http://e/p> \"b\"@en .\n"
  let crlf = string.replace(lf, "\n", "\r\n")
  ntriples.parse(crlf) |> should.equal(ntriples.parse(lf))
  nquads.parse(crlf) |> should.equal(nquads.parse(lf))
  let assert Ok(document) = ntriples.parse(crlf)
  graph.size(document.graph) |> should.equal(2)
}

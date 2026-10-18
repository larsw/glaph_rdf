# RDF Streaming Operations

glaph_rdf can read and write the line-based formats **N-Triples** (`.nt`) and **N-Quads** (`.nq`) one line at a time, instead of holding the whole file text in memory. These formats suit streaming because every statement is self-contained on its own line.

| Function | Reads/writes | Memory held |
|----------|--------------|-------------|
| `streaming_fold_file(path, from:, with:)` | one line at a time | the current line plus your accumulator (constant if your accumulator is) |
| `streaming_parse_file(path)` | one line at a time | the resulting graph/dataset (grows with the number of statements) |
| `streaming_serialize_to_file(graph_or_dataset, path)` | batches of lines | the input graph/dataset, plus one small batch of output text |

All of them are available in both `glaph_rdf/serializers/ntriples` and `glaph_rdf/serializers/nquads`, and work on both the Erlang and JavaScript targets.

## Constant-memory processing: `streaming_fold_file`

Use `streaming_fold_file` when the data may not fit in memory, or when you only need an aggregate (counts, filters, statistics, conversion). The callback receives every statement in file order, duplicates included. Blank lines and comments are skipped.

```gleam
import gleam/int
import gleam/io
import glaph_rdf/serializers/ntriples

pub fn count_triples(path: String) -> Nil {
  case ntriples.streaming_fold_file(path, from: 0, with: fn(count, _triple) {
    count + 1
  }) {
    Ok(count) -> io.println(int.to_string(count) <> " triples")
    Error(ntriples.NTriplesError(message, line)) ->
      io.println(message <> " (line " <> int.to_string(line) <> ")")
  }
}
```

The N-Quads version passes a `statement.Quad`; statements without a graph label are in `term.DefaultGraph`:

```gleam
import glaph_rdf/serializers/nquads
import glaph_rdf/statement
import glaph_rdf/term

let count_named = fn(count: Int, quad: statement.Quad) {
  case quad.graph {
    term.DefaultGraph -> count
    _ -> count + 1
  }
}
let result = nquads.streaming_fold_file("large.nq", from: 0, with: count_named)
// -> Ok(number of quads in named graphs) or Error(nquads.NQuadsError(..))
```

## Loading a whole file: `streaming_parse_file`

`streaming_parse_file` reads the file line by line, so the file text is never loaded as one string, but it still builds the complete graph or dataset in memory. Its result is equal (`==`) to what `parse_file` returns for the same file, including statement order and duplicate removal; graphs are built with an O(n log n) bulk constructor.

```gleam
import gleam/int
import gleam/io
import glaph_rdf/graph
import glaph_rdf/serializers/ntriples

case ntriples.streaming_parse_file("dataset.nt") {
  Ok(document) ->
    io.println(int.to_string(graph.size(document.graph)) <> " triples")
  Error(ntriples.NTriplesError(message, line)) ->
    io.println(message <> " (line " <> int.to_string(line) <> ")")
}
```

`nquads.streaming_parse_file(path)` works the same way and returns `Result(nquads.NQuadsDocument, nquads.NQuadsError)`.

## Writing: `streaming_serialize_to_file`

`streaming_serialize_to_file` writes the statements in batches instead of building the whole document as one string. The file content is byte-for-byte the same as `ntriples.serialize_graph` / `nquads.serialize_dataset`. The file is created or truncated.

```gleam
import gleam/io
import glaph_rdf/serializers/nquads

case nquads.streaming_serialize_to_file(my_dataset, "output.nq") {
  Ok(Nil) -> io.println("Written")
  Error(nquads.NQuadsError(message, _line)) -> io.println(message)
}
```

Errors that only surface when the file is closed (buffered writes failing on a full disk, for example) are reported too.

## Error handling

The streaming functions return the same error types as their non-streaming siblings, so you never need to import `file_streams` yourself:

- `ntriples.NTriplesError(message: String, line: Int)`
- `nquads.NQuadsError(message: String, line: Int)`

| Failure | `message` | `line` |
|---------|-----------|--------|
| Syntax error | the parser's message, identical to `parse_file` | the offending line (1-based, counting blank and comment lines) |
| Invalid UTF-8 | `"File error: Invalid UTF-8 (<path>)"` | the offending line |
| Opening, writing or closing the file | `"File error: <description> (<path>)"`, e.g. `"File error: No such file or directory (data.nt)"` | `0` |
| Reading the file | `"File error: <description> (<path>)"` | the line that could not be read |

For a syntax error, `streaming_parse_file(path)` and `parse_file(path)` return exactly the same error value. This also holds for CRLF files: both strip one trailing CR from every line before parsing it. The two differ only for invalid UTF-8, where `parse_file` reports `"File error: File read error (<path>)"` with line `0` because it decodes the whole file at once.

```gleam
import gleam/int
import gleam/io
import glaph_rdf/serializers/ntriples

case ntriples.streaming_parse_file(path) {
  Ok(document) -> process_document(document)
  Error(ntriples.NTriplesError(message, 0)) ->
    io.println("Could not access the file: " <> message)
  Error(ntriples.NTriplesError(message, line)) ->
    io.println("Line " <> int.to_string(line) <> ": " <> message)
}
```

## Combining with in-memory operations

```gleam
import gleam/list
import gleam/result
import glaph_rdf/graph
import glaph_rdf/serializers/ntriples
import glaph_rdf/statement

pub fn filter_file(
  keep: fn(statement.Triple) -> Bool,
) -> Result(Nil, ntriples.NTriplesError) {
  use document <- result.try(ntriples.streaming_parse_file("large.nt"))
  let filtered =
    document.graph
    |> graph.triples
    |> list.filter(keep)
    |> graph.from_list
  ntriples.streaming_serialize_to_file(filtered, "filtered.nt")
}
```

To filter a file that does not fit in memory, collect only the matching triples with `streaming_fold_file` instead:

```gleam
use kept <- result.try(
  ntriples.streaming_fold_file("large.nt", from: [], with: fn(acc, triple) {
    case keep(triple) {
      True -> [triple, ..acc]
      False -> acc
    }
  }),
)
ntriples.streaming_serialize_to_file(
  graph.from_list(list.reverse(kept)),
  "filtered.nt",
)
```

## Implementation notes

- Files are read in 64 KiB chunks and split into lines by an internal line reader. It accepts LF and CRLF line endings, a missing final newline, and multi-byte UTF-8 characters that straddle chunk boundaries.
- A UTF-8 byte order mark (U+FEFF) at the very start of the file is skipped, as `parse_file` does. U+FEFF anywhere else, including at the start of a later line, is a syntax error, on both targets.
- The file is always closed, also when parsing or writing fails.
- Streaming parsing gives the same results on Erlang and JavaScript.

## Examples

See `test/streaming_test.gleam` for tested examples of every function above.

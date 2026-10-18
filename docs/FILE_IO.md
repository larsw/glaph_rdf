# RDF File I/O Support

This document provides comprehensive documentation for the file input/output functionality in glaph_rdf serializers.

## Overview

All RDF serializers in glaph_rdf support direct file operations in addition to string-based serialization. `parse_file` and `serialize_to_file` read or write the whole file content at once. For large N-Triples and N-Quads files, the streaming functions read and write line by line instead; see [STREAMING.md](STREAMING.md).

## Supported Formats

### File I/O Support Matrix

| Format | Parse File | Parse Content | Serialize File | Serialize Content |
|--------|------------|---------------|----------------|-------------------|
| **Turtle** | ✅ `parse_file()` | ✅ `parse_graph_file()` | ✅ `serialize_to_file()` | ✅ `serialize_graph_to_file()` |
| **TriG** | ✅ `parse_file()` | ✅ `parse_dataset_file()` | ✅ `serialize_to_file()` | ✅ `serialize_dataset_to_file()` |
| **N-Triples** | ✅ `parse_file()` | ✅ `parse_graph_file()` | ✅ `serialize_to_file()` | ✅ `serialize_graph_to_file()` |
| **N-Quads** | ✅ `parse_file()` | ✅ `parse_dataset_file()` | ✅ `serialize_to_file()` | ✅ `serialize_dataset_to_file()` |

## File Operations

### Dependencies

File I/O operations use the `simplifile` library for cross-platform file handling:

```gleam
// Added automatically when using glaph_rdf
import simplifile
```

### Error Handling

All file operations return detailed error information including:
- File not found (`Enoent`)
- Permission denied (`Eacces`) 
- Path is a directory (`Eisdir`)
- No space left on device (`Enospc`)
- Generic file read/write errors

Error messages include the file path for debugging:
```gleam
Error(TurtleError("File error: File not found (/path/to/file.ttl)", 0))
```

## Turtle File I/O

### Reading Turtle Files

#### Parse Complete Document
```gleam
import glaph_rdf/serializers/turtle

case turtle.parse_file("data/ontology.ttl") {
  Ok(document) -> {
    // Access document.base, document.prefixes, document.graph
    let triple_count = graph.size(document.graph)
    let base_uri = document.base
    let prefixes = document.prefixes
  }
  Error(turtle.TurtleError(message, position)) -> {
    // Handle file read or parsing error
  }
}
```

#### Parse Graph Content Only
```gleam
case turtle.parse_graph_file("data/simple.ttl") {
  Ok(rdf_graph) -> {
    // Work directly with RDF graph
    let triples = graph.triples(rdf_graph)
  }
  Error(error) -> // Handle error
}
```

### Writing Turtle Files

#### Serialize Complete Document
```gleam
let document = turtle.TurtleDocument(
  base: Some("http://example.org/"),
  prefixes: dict.from_list([
    ("ex", "http://example.org/"),
    ("foaf", "http://xmlns.com/foaf/0.1/")
  ]),
  graph: my_graph
)

case turtle.serialize_to_file(document, "output/ontology.ttl") {
  Ok(Nil) -> // File written successfully
  Error(turtle.TurtleError(message, _)) -> // Handle write error
}
```

#### Serialize Graph with Options
```gleam
let prefixes = dict.from_list([
  ("ex", "http://example.org/"),
  ("foaf", "http://xmlns.com/foaf/0.1/")
])

case turtle.serialize_graph_to_file(
  my_graph,
  Some("http://example.org/"), // base URI
  prefixes,
  "output/data.ttl"
) {
  Ok(Nil) -> // Success
  Error(error) -> // Handle error
}
```

## TriG File I/O

### Reading TriG Files

#### Parse Complete Document
```gleam
import glaph_rdf/serializers/trig

case trig.parse_file("data/dataset.trig") {
  Ok(document) -> {
    // Access multi-graph dataset
    let graph_names = dataset.graph_names(document.dataset)
    let default_graph = dataset.default_graph(document.dataset)
  }
  Error(trig.TrigError(message, position)) -> {
    // Handle error
  }
}
```

#### Parse Dataset Content Only
```gleam
case trig.parse_dataset_file("data/knowledge_base.trig") {
  Ok(rdf_dataset) -> {
    // Work with multi-graph dataset
    let quad_count = dataset.quad_count(rdf_dataset)
    let graph_names = dataset.graph_names(rdf_dataset)
  }
  Error(error) -> // Handle error
}
```

### Writing TriG Files

#### Serialize Complete Document
```gleam
let document = trig.TrigDocument(
  base: Some("http://example.org/"),
  prefixes: dict.from_list([
    ("ex", "http://example.org/"),
    ("foaf", "http://xmlns.com/foaf/0.1/")
  ]),
  dataset: my_dataset
)

case trig.serialize_to_file(document, "output/dataset.trig") {
  Ok(Nil) -> // File written successfully  
  Error(error) -> // Handle write error
}
```

#### Serialize Dataset with Options
```gleam
case trig.serialize_dataset_to_file(
  my_dataset,
  Some("http://example.org/"), // base URI
  prefixes,
  "output/knowledge_base.trig"
) {
  Ok(Nil) -> // Success
  Error(error) -> // Handle error
}
```

## N-Triples File I/O

### Reading N-Triples Files

```gleam
import glaph_rdf/serializers/ntriples

// Parse complete document
case ntriples.parse_file("data/triples.nt") {
  Ok(document) -> {
    let triple_count = graph.size(document.graph)
  }
  Error(ntriples.NTriplesError(message, line)) -> {
    // Error includes line number
  }
}

// Parse graph content only
case ntriples.parse_graph_file("data/simple.nt") {
  Ok(rdf_graph) -> {
    // Work directly with graph
  }
  Error(error) -> // Handle error
}
```

### Writing N-Triples Files

```gleam
// Serialize document
let document = ntriples.NTriplesDocument(graph: my_graph)
case ntriples.serialize_to_file(document, "output/triples.nt") {
  Ok(Nil) -> // Success
  Error(error) -> // Handle error
}

// Serialize graph directly
case ntriples.serialize_graph_to_file(my_graph, "output/data.nt") {
  Ok(Nil) -> // Success  
  Error(error) -> // Handle error
}
```

## N-Quads File I/O

### Reading N-Quads Files

```gleam
import glaph_rdf/serializers/nquads

// Parse complete document
case nquads.parse_file("data/dataset.nq") {
  Ok(document) -> {
    let quad_count = dataset.quad_count(document.dataset)
  }
  Error(nquads.NQuadsError(message, line)) -> {
    // Error includes line number
  }
}

// Parse dataset content only
case nquads.parse_dataset_file("data/quads.nq") {
  Ok(rdf_dataset) -> {
    // Work directly with dataset
  }
  Error(error) -> // Handle error
}
```

### Writing N-Quads Files

```gleam
// Serialize document
let document = nquads.NQuadsDocument(dataset: my_dataset)
case nquads.serialize_to_file(document, "output/dataset.nq") {
  Ok(Nil) -> // Success
  Error(error) -> // Handle error
}

// Serialize dataset directly
case nquads.serialize_dataset_to_file(my_dataset, "output/quads.nq") {
  Ok(Nil) -> // Success
  Error(error) -> // Handle error
}
```

## Advanced Usage Patterns

### Round-Trip File Processing

```gleam
// Verify data integrity through serialization round-trip
let original_graph = my_graph

// Write to file
let _ = turtle.serialize_graph_to_file(
  original_graph, 
  None, 
  dict.new(), 
  "temp/test.ttl"
)

// Read back from file  
case turtle.parse_graph_file("temp/test.ttl") {
  Ok(parsed_graph) -> {
    // Verify semantic equivalence
    graph.isomorphic(original_graph, parsed_graph) |> should.be_true()
  }
  Error(_) -> should.fail()
}
```

### Cross-Format Conversion

```gleam
// Convert between RDF formats
case turtle.parse_graph_file("input/data.ttl") {
  Ok(graph) -> {
    // Convert to N-Triples
    case ntriples.serialize_graph_to_file(graph, "output/data.nt") {
      Ok(Nil) -> // Conversion successful
      Error(_) -> // Handle conversion error
    }
  }
  Error(_) -> // Handle read error
}
```

### Batch Processing

```gleam
let input_files = ["data1.ttl", "data2.ttl", "data3.ttl"]
let merged_graph = graph.new()

// Read and merge multiple files
let final_graph = list.fold(input_files, merged_graph, fn(acc, file) {
  case turtle.parse_graph_file(file) {
    Ok(file_graph) -> graph.merge(into: acc, from: file_graph)
    Error(_) -> acc // Skip problematic files
  }
})

// Write merged result
turtle.serialize_graph_to_file(
  final_graph,
  None,
  dict.new(),
  "output/merged.ttl"
)
```

### Large Dataset Processing

```gleam
// Process large datasets efficiently
case nquads.parse_dataset_file("large_dataset.nq") {
  Ok(dataset) -> {
    // Process each named graph separately
    dataset.graph_names(dataset)
    |> list.each(fn(graph_name) {
      let individual_graph = dataset.graph(dataset, graph_name)
      
      // Process individual graph
      let processed_graph = process_graph(individual_graph)
      
      // Write to separate file
      let filename = "output/graph_" <> graph_name_to_string(graph_name) <> ".ttl"
      turtle.serialize_graph_to_file(processed_graph, None, dict.new(), filename)
    })
  }
  Error(_) -> // Handle error
}
```

### Error Recovery and Validation

```gleam
pub fn safe_parse_file(path: String) -> Result(graph.Graph, String) {
  case turtle.parse_graph_file(path) {
    Ok(graph) -> Ok(graph)
    Error(turtle.TurtleError(message, position)) -> {
      // Try alternative formats
      case ntriples.parse_graph_file(path) {
        Ok(graph) -> Ok(graph)
        Error(_) -> Error("Failed to parse " <> path <> ": " <> message)
      }
    }
  }
}
```

## Encoding and Line Endings

- Files are read as UTF-8. A file that is not valid UTF-8 gives a `"File error: File read error (<path>)"` error with position/line `0`.
- A UTF-8 byte order mark (U+FEFF) at the very start of a file is skipped by every `parse_file` function and by the streaming parsers. U+FEFF anywhere else is parsed as ordinary text, so in N-Triples and N-Quads it is a syntax error. `parse(text)` never skips it. All of this behaves the same on Erlang and JavaScript.
- N-Triples and N-Quads accept LF and CRLF line endings: `parse`, `parse_file` and the streaming parsers all strip one trailing CR from each line, so a CRLF file gives the same result, and the same error for a bad line, as its LF version.

## Performance Considerations

### Memory Usage
- **`parse_file` / `serialize_to_file`**: Read or write the whole file content as one string, in addition to the parsed graph or dataset
- **Streaming (N-Triples and N-Quads only)**: `streaming_parse_file` reads one line at a time but still holds the resulting graph/dataset; `streaming_fold_file` processes statements one at a time in constant memory; `streaming_serialize_to_file` writes in batches. See [STREAMING.md](STREAMING.md)
- **Caching**: Consider caching parsed results for frequently accessed files

### File Size Recommendations
- **Small and medium files**: `parse_file` / `serialize_to_file` in any format
- **Large N-Triples/N-Quads files**: `streaming_parse_file` and `streaming_serialize_to_file` avoid holding the file text in memory
- **Files whose statements do not fit in memory**: `streaming_fold_file`, or convert Turtle/TriG to N-Triples/N-Quads first

### Optimizations
- Use format-specific parsers when file format is known
- Batch multiple file operations when possible
- Consider parallel processing for multiple independent files

## Integration with Existing APIs

### With Graph Operations
```gleam
// Load, process, and save
case turtle.parse_graph_file("input.ttl") {
  Ok(graph) -> {
    let processed = graph
      |> graph.add(new_triple)
      |> graph.remove(old_triple)
    
    turtle.serialize_graph_to_file(processed, None, prefixes, "output.ttl")
  }
  Error(_) -> Error("Processing failed")
}
```

### With Isomorphism Checking
```gleam
// Compare files for semantic equivalence
case turtle.parse_graph_file("file1.ttl"), turtle.parse_graph_file("file2.ttl") {
  Ok(graph1), Ok(graph2) -> {
    graph.isomorphic(graph1, graph2) // True if semantically equivalent
  }
  _, _ -> False
}
```

### With Serialization Options
```gleam
// Use consistent prefixes across operations
let standard_prefixes = dict.from_list([
  ("rdf", "http://www.w3.org/1999/02/22-rdf-syntax-ns#"),
  ("rdfs", "http://www.w3.org/2000/01/rdf-schema#"),
  ("owl", "http://www.w3.org/2002/07/owl#"),
  ("xsd", "http://www.w3.org/2001/XMLSchema#")
])

// Apply to all file operations
turtle.serialize_graph_to_file(graph, base_uri, standard_prefixes, output_path)
```

## Future Enhancements

### Planned Features
- **Streaming for Turtle/TriG**: N-Triples and N-Quads already support streaming (see [STREAMING.md](STREAMING.md))
- **Compression Support**: Automatic handling of `.gz`, `.bz2`, and other compressed formats
- **Parallel Processing**: Multi-threaded file operations for better performance
- **Progress Callbacks**: Monitor progress for large file operations
- **Incremental Updates**: Append to existing files instead of full rewrites

### API Extensions
- **Async Operations**: Non-blocking file I/O for better concurrency
- **Custom Encodings**: Support for different text encodings beyond UTF-8  
- **Validation Hooks**: Pre-process validation before writing files
- **Format Detection**: Automatic format detection based on file content

## Best Practices

### File Handling
1. **Always handle errors**: File operations can fail for many reasons
2. **Use absolute paths**: Avoid relative path issues
3. **Validate inputs**: Check file existence and permissions before processing
4. **Clean up resources**: Temporary files should be removed after use

### Performance
1. **Choose appropriate format**: N-Triples/N-Quads for large datasets, Turtle/TriG for human readability
2. **Batch operations**: Group multiple file operations together
3. **Memory awareness**: Monitor memory usage with large files
4. **Error recovery**: Implement fallback strategies for corrupted files

### Maintainability  
1. **Consistent prefixes**: Use standard namespace prefixes across your application
2. **Error logging**: Log detailed error information for debugging
3. **Testing**: Include file I/O operations in your test suites
4. **Documentation**: Document expected file formats and locations

## Testing File I/O

The library includes comprehensive tests for all file operations with **platform-agnostic temporary file handling**:

```gleam
import glaph_rdf/serializers/turtle
import gleeunit/should
import envoy

// Platform-agnostic temporary directory helper
fn get_temp_dir() -> String {
  case envoy.get("TMPDIR") {
    Ok(dir) -> dir
    Error(_) ->
      case envoy.get("TMP") {
        Ok(dir) -> dir  
        Error(_) ->
          case envoy.get("TEMP") {
            Ok(dir) -> dir
            Error(_) -> "/tmp"  // Unix default
          }
      }
  }
}

pub fn test_turtle_round_trip() {
  let test_path = get_temp_file_path("test.ttl")
  let graph = create_test_graph()
  
  // Write file
  turtle.serialize_graph_to_file(graph, None, dict.new(), test_path)
  |> should.be_ok()
  
  // Read file  
  turtle.parse_graph_file(test_path)
  |> should.be_ok()
  
  // Clean up
  simplifile.delete(test_path)
}
```

**Cross-Platform Testing Features:**
- **Environment Variable Detection**: Automatically detects `TMPDIR`, `TMP`, and `TEMP` environment variables
- **OS-Specific Defaults**: Falls back to `/tmp` on Unix-like systems and `C:\Windows\Temp` on Windows  
- **Unique File Names**: Uses system timestamps to avoid test conflicts
- **Path Separator Handling**: Automatically uses correct path separators (`/` or `\`) based on platform

Run tests with: `gleam test`

The file I/O functionality provides a solid foundation for efficient RDF data processing while maintaining the same high-quality APIs and comprehensive error handling as the existing string-based serializers.
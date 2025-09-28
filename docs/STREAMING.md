# RDF Streaming Operations

This document describes the streaming operations available in glaph_rdf for efficient processing of large RDF files.

## Overview

The streaming operations allow you to process large RDF files without loading the entire content into memory. This is particularly useful for:

- Large N-Triples and N-Quads files that exceed available memory
- Processing RDF data in constrained memory environments
- Real-time processing of RDF data streams
- ETL operations on large RDF datasets

## Supported Formats

Streaming operations are currently supported for line-based RDF formats:

- **N-Triples** (`.nt`) - Each triple on its own line
- **N-Quads** (`.nq`) - Each quad on its own line

These formats are ideal for streaming because they can be processed line by line without requiring context from other parts of the file.

## N-Triples Streaming

### Streaming Parse from File

```gleam
import glaph_rdf/serializers/ntriples

case ntriples.streaming_parse_file("large_dataset.nt") {
  Ok(document) -> {
    // Successfully parsed the entire file
    let triple_count = graph.size(document.graph)
    io.println("Loaded " <> int.to_string(triple_count) <> " triples")
  }
  Error(file_stream_error.Enoent) -> 
    io.println("File not found")
  Error(file_stream_error.Eacces) -> 
    io.println("Permission denied")
  Error(_) -> 
    io.println("Error reading file")
}
```

### Streaming Serialize to File

```gleam
let large_graph = create_my_graph()

case ntriples.streaming_serialize_to_file(large_graph, "output.nt") {
  Ok(Nil) -> 
    io.println("Successfully written to file")
  Error(file_stream_error.Enospc) -> 
    io.println("No space left on device")
  Error(_) -> 
    io.println("Error writing file")
}
```

## N-Quads Streaming

### Streaming Parse from File

```gleam
import glaph_rdf/serializers/nquads

case nquads.streaming_parse_file("large_dataset.nq") {
  Ok(document) -> {
    // Successfully parsed the entire file
    let quad_count = dataset.quad_count(document.dataset)
    io.println("Loaded " <> int.to_string(quad_count) <> " quads")
  }
  Error(file_stream_error.Enoent) -> 
    io.println("File not found")
  Error(_) -> 
    io.println("Error reading file")
}
```

### Streaming Serialize to File

```gleam
let large_dataset = create_my_dataset()

case nquads.streaming_serialize_to_file(large_dataset, "output.nq") {
  Ok(Nil) -> 
    io.println("Successfully written to file")
  Error(_) -> 
    io.println("Error writing file")
}
```

## Performance Benefits

### Memory Usage

Streaming operations provide significant memory benefits:

- **Regular parsing**: Loads entire file content into memory at once
- **Streaming parsing**: Processes one line at a time, constant memory usage

### Example Memory Comparison

```gleam
// Regular parsing - loads entire file into memory
let content = simplifile.read("1gb_file.nt")  // Uses ~1GB RAM
let document = ntriples.parse(content)

// Streaming parsing - constant memory usage
let document = ntriples.streaming_parse_file("1gb_file.nt")  // Uses ~few KB RAM
```

### Throughput

Streaming operations can actually be faster for large files because:

1. No need to allocate memory for the entire file content
2. Reduced garbage collection pressure  
3. Better CPU cache utilization
4. Can start processing immediately (no need to wait for entire file to load)

## Error Handling

Streaming operations return `file_stream_error.FileStreamError` types that provide detailed error information:

```gleam
import file_streams/file_stream_error

case ntriples.streaming_parse_file(filename) {
  Ok(document) -> process_document(document)
  Error(file_stream_error.Enoent) -> io.println("File not found")
  Error(file_stream_error.Eacces) -> io.println("Permission denied")
  Error(file_stream_error.Enospc) -> io.println("No space left on device")
  Error(file_stream_error.Eio) -> io.println("I/O error or parse error")
  Error(file_stream_error.Eof) -> io.println("Unexpected end of file")
  Error(err) -> {
    io.println("Other error: " <> file_stream_error.describe(err))
  }
}
```

## Best Practices

### When to Use Streaming

Use streaming operations when:

- File size > 100MB
- Available memory < 2x file size
- Processing files in server environments with memory constraints
- Building ETL pipelines for RDF data
- Real-time processing requirements

### When to Use Regular Operations

Use regular file I/O operations when:

- File size < 50MB
- Need random access to triples/quads
- Building interactive applications
- Memory is abundant

### Combining with Other Operations

Streaming operations work well with other glaph_rdf features:

```gleam
// Stream large file, then use in-memory operations
case ntriples.streaming_parse_file("large.nt") {
  Ok(document) -> {
    // Now use regular operations on the loaded graph
    let filtered_graph = document.graph
    |> graph.triples
    |> list.filter(some_predicate)
    |> graph.from_list
    
    // Stream the filtered results to a new file
    ntriples.streaming_serialize_to_file(filtered_graph, "filtered.nt")
  }
  Error(_) -> io.println("Failed to load")
}
```

## Implementation Details

### Line-by-Line Processing

The streaming implementation reads and processes one line at a time:

1. Open file stream
2. Read line
3. Parse line to RDF triple/quad  
4. Add to accumulating graph/dataset
5. Repeat until EOF
6. Close file stream

### Memory Management

- Only one line is held in memory at any time
- Graph/dataset grows incrementally 
- Automatic cleanup of file handles
- Error recovery with proper resource management

### Platform Support

Streaming operations work on all platforms supported by the file_streams library:

- Erlang target: Full support
- JavaScript target: Full support with some limitations (see file_streams documentation)

## Dependencies

Streaming operations require the `file_streams` library which is automatically included:

```toml
# In gleam.toml
[dependencies]
file_streams = ">= 1.6.0 and < 2.0.0"
```

## Examples

See `test/streaming_test.gleam` for comprehensive examples and `src/streaming_demo.gleam` for a working demonstration.
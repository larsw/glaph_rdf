import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri

const ascii_letters = [
  "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p",
  "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
]

const irregular_language_tags = [
  "en-gb-oed",
  "i-ami",
  "i-bnn",
  "i-default",
  "i-enochian",
  "i-hak",
  "i-klingon",
  "i-lux",
  "i-mingo",
  "i-navajo",
  "i-pwn",
  "i-tao",
  "i-tay",
  "i-tsu",
  "sgn-be-fr",
  "sgn-be-nl",
  "sgn-ch-de",
]

const regular_language_tags = [
  "art-lojban",
  "cel-gaulish",
  "no-bok",
  "no-nyn",
  "zh-guoyu",
  "zh-hakka",
  "zh-min",
  "zh-min-nan",
  "zh-xiang",
]

fn grandfathered_language_tags() -> List(String) {
  list.flatten([irregular_language_tags, regular_language_tags])
}

/// Errors that can occur when creating or validating RDF terms.
pub type TermError {
  /// The provided string is not a valid IRI according to RFC 3987.
  InvalidIri(String)
  /// The provided string is not a valid blank node identifier.
  InvalidBlankNodeIdentifier(String)
  /// The provided string is not a valid BCP 47 language tag.
  InvalidLanguageTag(String)
  /// A literal cannot be used as a subject in RDF.
  InvalidSubjectTerm
  /// A literal or quoted triple cannot be used as a graph name.
  InvalidGraphNameTerm
}

/// An RDF named node (IRI reference) that identifies a resource.
/// 
/// Named nodes must be valid IRIs according to RFC 3987. They are used to 
/// identify resources, properties, classes, and other entities in RDF data.
pub type NamedNode {
  NamedNode(value: String)
}

/// An RDF blank node representing an unnamed resource.
///
/// Blank nodes have local identifiers that are unique within a graph but
/// have no global meaning. They represent existential quantification.
pub type BlankNode {
  BlankNode(identifier: String)
}

/// A BCP 47 language tag for language-tagged literals.
///
/// Language tags follow the BCP 47 specification and are canonicalized
/// with proper casing (e.g., "en-US", "zh-Hant-TW").
pub type LanguageTag {
  LanguageTag(value: String)
}

/// An RDF literal representing a value with optional language or datatype.
///
/// Literals can be:
/// - Simple: plain string values
/// - Language-tagged: strings with BCP 47 language tags  
/// - Typed: values with explicit XML Schema datatypes
pub type Literal {
  /// A simple literal with just a string value.
  SimpleLiteral(value: String)
  /// A literal with a string value and BCP 47 language tag.
  LanguageTaggedLiteral(value: String, tag: LanguageTag)
  /// A literal with a string value and explicit datatype IRI.
  TypedLiteral(value: String, datatype: NamedNode)
}

/// An RDF-star quoted triple that can be used as a subject or object.
///
/// Triple terms enable making statements about statements (reification).
/// They are serialized using << >> syntax in RDF-star formats.
/// 
/// ## Example
/// ```gleam
/// let quoted = triple_term(
///   SubjectNamed(unsafe_named_node("http://example.org/alice")),
///   unsafe_named_node("http://xmlns.com/foaf/0.1/name"), 
///   ObjectLiteral(simple_literal("Alice"))
/// )
/// // Represents: <<ex:alice foaf:name "Alice">>
/// ```
pub type TripleTerm {
  TripleTerm(subject: Subject, predicate: Predicate, object: Object)
}

/// A general RDF term that can be a named node, blank node, literal, or quoted triple.
///
/// This is the most general type that encompasses all possible RDF terms
/// including RDF-star quoted triples.
pub type Term {
  /// A named node (IRI reference).
  NamedTerm(node: NamedNode)
  /// A blank node with local identifier.
  BlankTerm(node: BlankNode)
  /// A literal value (simple, language-tagged, or typed).
  LiteralTerm(literal: Literal)
  /// An RDF-star quoted triple term.
  QuotedTripleTerm(triple: TripleTerm)
}

/// The subject position of an RDF triple.
///
/// Subjects can be named nodes, blank nodes, or RDF-star quoted triples.
/// Literals cannot be subjects in RDF.
pub type Subject {
  /// A named node subject.
  SubjectNamed(node: NamedNode)
  /// A blank node subject.
  SubjectBlank(node: BlankNode)
  /// An RDF-star quoted triple as subject.
  SubjectTriple(triple: TripleTerm)
}

/// The predicate position of an RDF triple.
///
/// Predicates must always be named nodes (IRIs) in RDF.
pub type Predicate =
  NamedNode

/// The object position of an RDF triple.
///
/// Objects can be named nodes, blank nodes, literals, or RDF-star quoted triples.
pub type Object {
  /// A named node object.
  ObjectNamed(node: NamedNode)
  /// A blank node object.
  ObjectBlank(node: BlankNode)
  /// A literal object.
  ObjectLiteral(literal: Literal)
  /// An RDF-star quoted triple as object.
  ObjectTriple(triple: TripleTerm)
}

/// The name/identifier of an RDF graph in a dataset.
///
/// Graphs can be the default graph (unnamed) or named graphs identified
/// by IRIs or blank nodes.
pub type GraphName {
  /// The default (unnamed) graph in a dataset.
  DefaultGraph
  /// A named graph identified by an IRI.
  NamedGraph(node: NamedNode)
  /// A named graph identified by a blank node.
  BlankGraph(node: BlankNode)
}

/// Create a named node from an IRI string with validation.
///
/// Validates that the provided string is a well-formed IRI according to RFC 3987
/// and RDF 1.2 restrictions. Returns an error if the IRI is invalid.
///
/// ## Examples
/// ```gleam
/// named_node("http://example.org/alice")  // Ok(NamedNode(...))
/// named_node("not-an-iri")                // Error(InvalidIri(...))
/// ```
pub fn named_node(value: String) -> Result(NamedNode, TermError) {
  case validate_iri(value) {
    True -> Ok(NamedNode(value))
    False -> Error(InvalidIri(value))
  }
}

/// Create a named node from an IRI string without validation.
///
/// **Warning**: This function bypasses IRI validation. Only use when you are
/// certain the IRI is valid to avoid creating invalid RDF. Prefer `named_node/1`
/// for safe construction with validation.
///
/// ## Examples
/// ```gleam
/// unsafe_named_node("http://example.org/alice")  // NamedNode(...)
/// ```
pub fn unsafe_named_node(value: String) -> NamedNode {
  NamedNode(value)
}

/// Create a blank node with validation of the identifier format.
///
/// Validates that the identifier follows RDF blank node identifier rules:
/// - Starts with an underscore or letter
/// - Followed by zero or more letters, digits, hyphens, or underscores
///
/// ## Examples
/// ```gleam
/// blank_node("n1")      // Ok(BlankNode("n1"))
/// blank_node("_:b42")   // Ok(BlankNode("_:b42"))
/// blank_node("123")     // Error(InvalidBlankNodeIdentifier("123"))
/// ```
pub fn blank_node(identifier: String) -> Result(BlankNode, TermError) {
  case is_valid_blank_node_identifier(identifier) {
    True -> Ok(BlankNode(identifier))
    False -> Error(InvalidBlankNodeIdentifier(identifier))
  }
}

/// Create a blank node without validation of the identifier.
///
/// **Warning**: This function bypasses identifier validation. Only use when you are
/// certain the identifier is valid to avoid creating invalid RDF. Prefer the
/// validated `blank_node/1` function for safe construction.
///
/// ## Examples
/// ```gleam
/// unsafe_blank_node("n1")  // BlankNode("n1")
/// ```
pub fn unsafe_blank_node(identifier: String) -> BlankNode {
  BlankNode(identifier)
}

/// Create a language tag from a BCP 47 language tag string with validation.
///
/// Validates and normalizes the language tag according to BCP 47 and RDF 1.2 rules.
/// Converts to canonical lowercase form and validates structure including language,
/// script, region, variants, and extensions.
///
/// ## Examples
/// ```gleam
/// language_tag("en-US")     // Ok(LanguageTag("en-us"))
/// language_tag("zh-Hant")   // Ok(LanguageTag("zh-hant"))  
/// language_tag("invalid")   // Error(InvalidLanguageTag("invalid"))
/// ```
pub fn language_tag(value: String) -> Result(LanguageTag, TermError) {
  let lower = string.lowercase(value)
  case canonical_language_tag(lower) {
    Ok(canonical) -> Ok(LanguageTag(canonical))
    Error(_) -> Error(InvalidLanguageTag(value))
  }
}

/// Create a simple string literal without language tag or datatype.
///
/// Simple literals represent plain text values in RDF. They are equivalent
/// to typed literals with the `xsd:string` datatype.
///
/// ## Examples
/// ```gleam
/// simple_literal("Hello World")  // SimpleLiteral("Hello World")
/// simple_literal("")             // SimpleLiteral("")
/// ```
pub fn simple_literal(value: String) -> Literal {
  SimpleLiteral(value)
}

/// Create a language-tagged string literal.
///
/// Language-tagged literals associate natural language text with a specific
/// language using BCP 47 language tags. Useful for internationalization
/// and multilingual content.
///
/// ## Examples
/// ```gleam
/// language_literal("Hello", LanguageTag("en"))      // LanguageTaggedLiteral(...)
/// language_literal("Bonjour", LanguageTag("fr"))    // LanguageTaggedLiteral(...)
/// ```
pub fn language_literal(value: String, tag: LanguageTag) -> Literal {
  LanguageTaggedLiteral(value, tag)
}

/// Create a typed literal with a specific datatype.
///
/// Typed literals associate a string value with an IRI that identifies
/// the datatype. Common datatypes include XSD types like integer, boolean,
/// dateTime, etc.
///
/// ## Examples
/// ```gleam
/// typed_literal("42", NamedNode("http://www.w3.org/2001/XMLSchema#int"))
/// typed_literal("true", NamedNode("http://www.w3.org/2001/XMLSchema#boolean"))
/// ```
pub fn typed_literal(value: String, datatype: NamedNode) -> Literal {
  TypedLiteral(value, datatype)
}

/// Create a quoted triple term for RDF-star from validated RDF terms.
///
/// Creates a quoted triple (also called a reified triple) that can be used
/// as a subject or object in other triples. This enables metadata about
/// statements in RDF-star.
///
/// ## Examples
/// ```gleam
/// let alice = SubjectNamed(NamedNode("http://example.org/alice"))
/// let knows = NamedNode("http://xmlns.com/foaf/0.1/knows")  
/// let bob = ObjectNamed(NamedNode("http://example.org/bob"))
/// triple_term(alice, knows, bob)  // TripleTerm(alice knows bob)
/// ```
pub fn triple_term(
  subject: Subject,
  predicate: Predicate,
  object: Object,
) -> TripleTerm {
  TripleTerm(subject, predicate, object)
}

/// Create a quoted triple term from IRI strings without validation.
///
/// **Warning**: This function bypasses IRI validation for all three terms.
/// Only use when you are certain all IRIs are valid. Prefer constructing
/// with validated terms and `triple_term/3` for safe construction.
///
/// ## Examples
/// ```gleam
/// unsafe_triple_term(
///   "http://example.org/alice",
///   "http://xmlns.com/foaf/0.1/knows", 
///   "http://example.org/bob"
/// )  // TripleTerm with named node terms
/// ```
pub fn unsafe_triple_term(
  subject_iri: String,
  predicate_iri: String,
  object_iri: String,
) -> TripleTerm {
  TripleTerm(
    SubjectNamed(unsafe_named_node(subject_iri)),
    unsafe_named_node(predicate_iri),
    ObjectNamed(unsafe_named_node(object_iri)),
  )
}

/// Convert a subject term to a general term.
///
/// Converts RDF subject positions (named nodes, blank nodes, or quoted triples
/// in RDF-star) to the general Term type for uniform handling.
///
/// ## Examples
/// ```gleam
/// term_from_subject(SubjectNamed(NamedNode("http://example.org/alice")))
/// // -> NamedTerm(NamedNode("http://example.org/alice"))
/// 
/// term_from_subject(SubjectBlank(BlankNode("b1")))
/// // -> BlankTerm(BlankNode("b1"))
/// ```
pub fn term_from_subject(subject: Subject) -> Term {
  case subject {
    SubjectNamed(node) -> NamedTerm(node)
    SubjectBlank(node) -> BlankTerm(node)
    SubjectTriple(triple) -> QuotedTripleTerm(triple)
  }
}

/// Convert an object term to a general term.
///
/// Converts RDF object positions (named nodes, blank nodes, literals, or 
/// quoted triples in RDF-star) to the general Term type for uniform handling.
///
/// ## Examples
/// ```gleam
/// term_from_object(ObjectLiteral(SimpleLiteral("Hello")))
/// // -> LiteralTerm(SimpleLiteral("Hello"))
/// 
/// term_from_object(ObjectNamed(NamedNode("http://example.org/bob")))
/// // -> NamedTerm(NamedNode("http://example.org/bob"))
/// ```
pub fn term_from_object(object: Object) -> Term {
  case object {
    ObjectNamed(node) -> NamedTerm(node)
    ObjectBlank(node) -> BlankTerm(node)
    ObjectLiteral(literal) -> LiteralTerm(literal)
    ObjectTriple(triple) -> QuotedTripleTerm(triple)
  }
}

/// Convert a general term to a subject term with validation.
///
/// Converts a general Term to a Subject, ensuring it contains only terms
/// that are valid in subject position (named nodes, blank nodes, or quoted
/// triples in RDF-star). Literals cannot be subjects in RDF.
///
/// ## Examples
/// ```gleam
/// subject_from_term(NamedTerm(NamedNode("http://example.org/alice")))
/// // -> Ok(SubjectNamed(...))
/// 
/// subject_from_term(LiteralTerm(SimpleLiteral("Hello")))
/// // -> Error(InvalidSubjectTerm)
/// ```
pub fn subject_from_term(term: Term) -> Result(Subject, TermError) {
  case term {
    NamedTerm(node) -> Ok(SubjectNamed(node))
    BlankTerm(node) -> Ok(SubjectBlank(node))
    LiteralTerm(_) -> Error(InvalidSubjectTerm)
    QuotedTripleTerm(triple) -> Ok(SubjectTriple(triple))
  }
}

/// Convert a general term to an object term.
///
/// Converts any Term to an Object. All RDF term types can appear in object
/// position, including named nodes, blank nodes, literals, and quoted triples
/// in RDF-star.
///
/// ## Examples
/// ```gleam
/// object_from_term(LiteralTerm(SimpleLiteral("Hello")))
/// // -> ObjectLiteral(SimpleLiteral("Hello"))
/// 
/// object_from_term(NamedTerm(NamedNode("http://example.org/bob")))  
/// // -> ObjectNamed(NamedNode("http://example.org/bob"))
/// ```
pub fn object_from_term(term: Term) -> Object {
  case term {
    NamedTerm(node) -> ObjectNamed(node)
    BlankTerm(node) -> ObjectBlank(node)
    LiteralTerm(literal) -> ObjectLiteral(literal)
    QuotedTripleTerm(triple) -> ObjectTriple(triple)
  }
}

/// Convert a general term to a graph name with validation.
///
/// Converts a Term to a GraphName for use in RDF datasets. Only named nodes
/// and blank nodes can be graph names. Literals and quoted triples cannot
/// identify graphs in RDF.
///
/// ## Examples
/// ```gleam
/// graph_name_from_term(NamedTerm(NamedNode("http://example.org/graph1")))
/// // -> Ok(NamedGraph(...))
/// 
/// graph_name_from_term(LiteralTerm(SimpleLiteral("invalid")))
/// // -> Error(InvalidGraphNameTerm)
/// ```
pub fn graph_name_from_term(term: Term) -> Result(GraphName, TermError) {
  case term {
    NamedTerm(node) -> Ok(NamedGraph(node))
    BlankTerm(node) -> Ok(BlankGraph(node))
    LiteralTerm(_) -> Error(InvalidGraphNameTerm)
    QuotedTripleTerm(_) -> Error(InvalidGraphNameTerm)
  }
}

/// Parse an IRI string into a URI structure with validation.
///
/// Converts an IRI (Internationalized Resource Identifier) string into
/// a structured URI representation, handling percent-encoding and validation
/// according to RFC 3987.
///
/// ## Examples
/// ```gleam
/// iri_to_uri("http://example.org/path")  // Ok(Uri(...))
/// iri_to_uri("not-valid-iri")           // Error(InvalidIri(...))
/// ```
pub fn iri_to_uri(value: String) -> Result(uri.Uri, TermError) {
  parse_encoded_iri(value)
}

/// Convert a URI structure back to an IRI string with decoding.
///
/// Converts a structured URI back to an IRI string representation,
/// handling percent-decoding of internationalized characters according
/// to RFC 3987 requirements.
///
/// ## Examples
/// ```gleam
/// uri_to_iri(some_uri)  // Ok("http://example.org/path")
/// ```
pub fn uri_to_iri(uri_value: uri.Uri) -> Result(String, TermError) {
  uri.to_string(uri_value)
  |> decode_iri
}

/// Convert a named node to a URI structure.
///
/// Extracts the IRI string from a named node and parses it into a structured
/// URI representation for manipulation or analysis.
///
/// ## Examples
/// ```gleam
/// let node = NamedNode("http://example.org/alice")
/// named_node_to_uri(node)  // Ok(Uri(...))
/// ```
pub fn named_node_to_uri(node: NamedNode) -> Result(uri.Uri, TermError) {
  let NamedNode(value) = node
  iri_to_uri(value)
}

/// Create a named node from a URI structure with validation.
///
/// Converts a structured URI to an IRI string and creates a validated
/// named node. The URI is converted to string form and then validated
/// according to RDF requirements.
///
/// ## Examples
/// ```gleam
/// named_node_from_uri(some_valid_uri)  // Ok(NamedNode(...))
/// ```
pub fn named_node_from_uri(uri_value: uri.Uri) -> Result(NamedNode, TermError) {
  uri_to_iri(uri_value)
  |> result.try(named_node)
}

/// Decode percent-encoded characters in an IRI string.
///
/// Processes an IRI string and decodes percent-encoded sequences (like %20 for space)
/// back to their original Unicode characters. Validates that the encoding is
/// well-formed according to RFC 3987.
///
/// ## Examples
/// ```gleam
/// decode_iri("http://example.org/hello%20world")  // Ok("http://example.org/hello world")
/// decode_iri("invalid%ZZ")                        // Error(InvalidIriEncoding(...))
/// ```
pub fn decode_iri(value: String) -> Result(String, TermError) {
  decode_iri_loop(string.to_graphemes(value), [], value)
}

fn decode_iri_loop(
  graphemes: List(String),
  acc: List(String),
  original: String,
) -> Result(String, TermError) {
  case graphemes {
    [] -> Ok(string.concat(list.reverse(acc)))
    ["%", ..] ->
      case decode_percent_sequence(graphemes) {
        Ok(#(segment, rest)) ->
          decode_iri_loop(rest, [segment, ..acc], original)

        Error(_) -> Error(InvalidIri(original))
      }
    [head, ..rest] -> decode_iri_loop(rest, [head, ..acc], original)
  }
}

fn decode_percent_sequence(
  graphemes: List(String),
) -> Result(#(String, List(String)), Nil) {
  take_percent_encoded(graphemes, [])
  |> result.try(fn(result) {
    let #(encoded, rest) = result
    case uri.percent_decode(encoded) {
      Ok(decoded) -> {
        let cp_ints =
          string.to_utf_codepoints(decoded)
          |> list.map(string.utf_codepoint_to_int)
        case list.all(cp_ints, fn(cp) { cp > 0x7F }) {
          True -> Ok(#(decoded, rest))
          False -> Ok(#(encoded, rest))
        }
      }
      Error(_) -> Error(Nil)
    }
  })
}

fn take_percent_encoded(
  graphemes: List(String),
  acc: List(String),
) -> Result(#(String, List(String)), Nil) {
  case graphemes {
    ["%", x, y, ..rest] ->
      case is_hex_digit(x) && is_hex_digit(y) {
        True -> take_percent_encoded(rest, [y, x, "%", ..acc])
        False -> Error(Nil)
      }
    _ ->
      case acc {
        [] -> Error(Nil)
        _ -> {
          let encoded = string.concat(list.reverse(acc))
          Ok(#(encoded, graphemes))
        }
      }
  }
}

fn validate_iri(value: String) -> Bool {
  case string.split_once(value, ":") {
    Ok(#(scheme, _rest)) ->
      is_valid_scheme(scheme)
      && has_valid_iri_syntax(value)
      && result.is_ok(parse_encoded_iri(with_placeholder_ip_literal(value)))

    Error(_) -> False
  }
}

/// Replaces an IPv6 literal host (already checked by `has_valid_iri_syntax`)
/// with `[::1]`. On JavaScript `uri.parse` rejects valid literals that contain
/// the hex letters b-f or an embedded IPv4 address, such as `[fe80::1]`, so
/// the literal is validated here and kept away from it.
fn with_placeholder_ip_literal(value: String) -> String {
  case string.split_once(value, "[") {
    Ok(#(before, after)) ->
      case string.split_once(after, "]") {
        Ok(#(_address, rest)) -> before <> "[::1]" <> rest
        Error(_) -> value
      }
    Error(_) -> value
  }
}

fn is_valid_scheme(scheme: String) -> Bool {
  case string.to_graphemes(scheme) {
    [] -> False
    [first, ..rest] ->
      is_ascii_letter(first)
      && list.all(rest, fn(char) {
        is_ascii_letter(char)
        || is_digit(char)
        || char == "+"
        || char == "-"
        || char == "."
      })
  }
}

fn parse_encoded_iri(value: String) -> Result(uri.Uri, TermError) {
  // `uri.parse` only rejects illegal characters on Erlang; the JavaScript
  // implementation accepts almost anything. Check the characters explicitly
  // first so validation gives the same answer on both targets.
  use <- bool.guard(!has_valid_iri_syntax(value), Error(InvalidIri(value)))
  case uri.parse(percent_encode_iri(value)) {
    Ok(parsed) -> Ok(parsed)
    Error(_) -> Error(InvalidIri(value))
  }
}

/// Target-independent checks for what RFC 3987 forbids in an IRI reference:
/// no control characters, space, DEL or any of `"<>\^`{|}`; at most one `#`;
/// at most one `@` in the authority; and square brackets only around an IPv6
/// literal host (`http://[::1]/`).
fn has_valid_iri_syntax(value: String) -> Bool {
  list.all(string.to_utf_codepoints(value), fn(codepoint) {
    is_allowed_iri_codepoint(string.utf_codepoint_to_int(codepoint))
  })
  && list.length(string.split(value, "#")) <= 2
  && has_valid_iri_brackets(value)
}

fn is_allowed_iri_codepoint(cp: Int) -> Bool {
  case cp {
    _ if cp <= 0x20 -> False
    // DEL " < > \ ^ ` { | }
    0x7F | 0x22 | 0x3C | 0x3E | 0x5C | 0x5E | 0x60 | 0x7B | 0x7C | 0x7D -> False
    _ -> True
  }
}

fn has_valid_iri_brackets(value: String) -> Bool {
  let after_scheme = case string.split_once(value, ":") {
    Ok(#(scheme, rest)) ->
      case is_valid_scheme(scheme) {
        True -> rest
        False -> value
      }
    Error(_) -> value
  }
  case after_scheme {
    "//" <> hier -> {
      let #(authority, rest) = split_authority(string.to_graphemes(hier), [])
      is_valid_authority_brackets(authority) && !has_brackets(rest)
    }
    _ -> !has_brackets(after_scheme)
  }
}

/// Splits after `//` at the first `/`, `?` or `#`.
fn split_authority(
  graphemes: List(String),
  acc: List(String),
) -> #(String, String) {
  case graphemes {
    [] -> #(string.concat(list.reverse(acc)), "")
    [char, ..] if char == "/" || char == "?" || char == "#" -> #(
      string.concat(list.reverse(acc)),
      string.concat(graphemes),
    )
    [char, ..rest] -> split_authority(rest, [char, ..acc])
  }
}

fn is_valid_authority_brackets(authority: String) -> Bool {
  let host_and_port = case string.split(authority, "@") {
    [host_and_port] -> Ok(host_and_port)
    [userinfo, host_and_port] ->
      case has_brackets(userinfo) {
        True -> Error(Nil)
        False -> Ok(host_and_port)
      }
    _ -> Error(Nil)
  }
  case host_and_port {
    Error(Nil) -> False
    Ok(host_and_port) -> is_valid_host_brackets(host_and_port)
  }
}

/// An RFC 3986 `IPv6address` inside `[...]`: eight 16-bit hex groups, or
/// fewer with a single `::`, where the last 32 bits may be written as an
/// IPv4 address. IPvFuture and zone identifiers are not accepted.
fn is_ip_literal_address(address: String) -> Bool {
  case string.split(address, "::") {
    [full] ->
      case ipv6_group_count(full) {
        Ok(8) -> True
        _ -> False
      }
    [head, tail] ->
      case ipv6_group_count(head), ipv6_group_count(tail) {
        Ok(h), Ok(t) ->
          h + t <= 7
          // An embedded IPv4 address may only come last.
          && { head == "" || !string.contains(head, ".") }
        _, _ -> False
      }
    _ -> False
  }
}

/// Number of 16-bit groups in a `:`-separated run of h16 groups, where the
/// last one may be an IPv4 address (counting as two). `""` has zero groups.
fn ipv6_group_count(groups: String) -> Result(Int, Nil) {
  case groups {
    "" -> Ok(0)
    _ -> count_ipv6_groups(string.split(groups, ":"), 0)
  }
}

fn count_ipv6_groups(groups: List(String), count: Int) -> Result(Int, Nil) {
  case groups {
    [] -> Ok(count)
    [last] ->
      case is_h16(last), is_ipv4_address(last) {
        True, _ -> Ok(count + 1)
        _, True -> Ok(count + 2)
        _, _ -> Error(Nil)
      }
    [group, ..rest] ->
      case is_h16(group) {
        True -> count_ipv6_groups(rest, count + 1)
        False -> Error(Nil)
      }
  }
}

fn is_h16(group: String) -> Bool {
  let chars = string.to_graphemes(group)
  let length = list.length(chars)
  length >= 1 && length <= 4 && list.all(chars, is_hex_digit)
}

fn is_ipv4_address(value: String) -> Bool {
  case string.split(value, ".") {
    [_, _, _, _] as octets -> list.all(octets, is_dec_octet)
    _ -> False
  }
}

fn is_dec_octet(octet: String) -> Bool {
  let chars = string.to_graphemes(octet)
  case chars, int.parse(octet) {
    ["0", _, ..], _ -> False
    [_, ..], Ok(n) ->
      list.length(chars) <= 3 && list.all(chars, is_digit) && n <= 255
    _, _ -> False
  }
}

fn is_valid_host_brackets(host_and_port: String) -> Bool {
  case host_and_port {
    "[" <> literal ->
      case string.split_once(literal, "]") {
        Ok(#(address, port)) ->
          is_ip_literal_address(address)
          && !has_brackets(port)
          && case port {
            "" -> True
            ":" <> _ -> True
            _ -> False
          }
        Error(_) -> False
      }
    _ -> !has_brackets(host_and_port)
  }
}

fn has_brackets(value: String) -> Bool {
  string.contains(value, "[") || string.contains(value, "]")
}

fn percent_encode_iri(value: String) -> String {
  value
  |> string.to_utf_codepoints
  |> list.map(encode_iri_codepoint)
  |> string.concat
}

fn encode_iri_codepoint(codepoint) -> String {
  let cp = string.utf_codepoint_to_int(codepoint)
  case cp <= 0x7F {
    True -> string.from_utf_codepoints([codepoint])
    False ->
      encode_codepoint_bytes(cp)
      |> list.map(percent_encode_byte)
      |> string.concat
  }
}

fn encode_codepoint_bytes(codepoint: Int) -> List(Int) {
  case codepoint {
    cp if cp <= 0x7F -> [cp]
    cp if cp <= 0x7FF -> [
      0xC0 + int.bitwise_shift_right(cp, 6),
      0x80 + int.bitwise_and(cp, 0x3F),
    ]
    cp if cp <= 0xFFFF -> [
      0xE0 + int.bitwise_shift_right(cp, 12),
      0x80 + int.bitwise_and(int.bitwise_shift_right(cp, 6), 0x3F),
      0x80 + int.bitwise_and(cp, 0x3F),
    ]
    cp if cp <= 0x10FFFF -> [
      0xF0 + int.bitwise_shift_right(cp, 18),
      0x80 + int.bitwise_and(int.bitwise_shift_right(cp, 12), 0x3F),
      0x80 + int.bitwise_and(int.bitwise_shift_right(cp, 6), 0x3F),
      0x80 + int.bitwise_and(cp, 0x3F),
    ]
    _ -> []
  }
}

fn percent_encode_byte(byte: Int) -> String {
  let upper = string.uppercase(int.to_base16(byte))
  case string.length(upper) {
    1 -> "%0" <> upper
    _ -> "%" <> upper
  }
}

fn is_valid_blank_node_identifier(identifier: String) -> Bool {
  case string.to_graphemes(identifier) {
    [] -> False
    [first, ..rest] ->
      is_valid_blank_head(first)
      && is_valid_blank_body(first)
      && list.all(rest, fn(char) { is_valid_blank_body(char) })
  }
}

fn is_valid_blank_head(char: String) -> Bool {
  is_ascii_letter(char) || char == "_"
}

fn is_valid_blank_body(char: String) -> Bool {
  is_ascii_letter(char) || is_digit(char) || char == "_" || char == "."
}

fn is_ascii_letter(char: String) -> Bool {
  case string.to_graphemes(string.lowercase(char)) {
    [single] -> list.any(ascii_letters, fn(letter) { letter == single })
    _ -> False
  }
}

fn is_digit(char: String) -> Bool {
  case char {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}

fn is_hex_digit(char: String) -> Bool {
  let lower = string.lowercase(char)
  case lower {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    "a" | "b" | "c" | "d" | "e" | "f" -> True
    _ -> False
  }
}

fn is_grandfathered_tag(tag: String) -> Bool {
  list.any(grandfathered_language_tags(), fn(existing) { existing == tag })
}

fn canonical_language_tag(value: String) -> Result(String, Nil) {
  case value {
    "" -> Error(Nil)
    _ ->
      case is_grandfathered_tag(value) {
        True -> Ok(value)
        False ->
          case string.split(value, "-") {
            ["x", ..rest] -> canonical_privateuse(rest)
            subtags -> build_canonical_langtag(subtags)
          }
      }
  }
}

fn canonical_privateuse(subtags: List(String)) -> Result(String, Nil) {
  case subtags {
    [] -> Error(Nil)
    tags -> {
      case list.all(tags, is_privateuse_subtag) {
        True -> {
          let lowered = list.map(tags, string.lowercase)
          Ok("x-" <> string.join(lowered, "-"))
        }
        False -> Error(Nil)
      }
    }
  }
}

fn build_canonical_langtag(subtags: List(String)) -> Result(String, Nil) {
  case subtags {
    [language, ..rest] -> {
      case validate_language_subtag(language) {
        False -> Error(Nil)
        True -> {
          let lang_len = string.length(language)
          let canonical_language = string.lowercase(language)
          let #(extlangs, after_extlangs) = case
            lang_len >= 2 && lang_len <= 3
          {
            True -> extract_extlangs(rest)
            False -> #([], rest)
          }
          let #(script, after_script) = extract_script(after_extlangs)
          let #(region, after_region) = extract_region(after_script)
          let #(variants, after_variants) = extract_variants(after_region)
          case extract_extensions(after_variants) {
            Ok(#(extensions, after_extensions)) ->
              case extract_privateuse(after_extensions) {
                Ok(#(privateuse, remainder)) ->
                  case remainder {
                    [] ->
                      Ok(assemble_canonical_language_tag(
                        canonical_language,
                        extlangs,
                        script,
                        region,
                        variants,
                        extensions,
                        privateuse,
                      ))
                    _ -> Error(Nil)
                  }
                Error(_) -> Error(Nil)
              }
            Error(_) -> Error(Nil)
          }
        }
      }
    }
    [] -> Error(Nil)
  }
}

fn assemble_canonical_language_tag(
  language: String,
  extlangs: List(String),
  script: Option(String),
  region: Option(String),
  variants: List(String),
  extensions: List(List(String)),
  privateuse: Option(List(String)),
) -> String {
  let base = list.append([language], list.map(extlangs, string.lowercase))
  let base = case script {
    Some(value) -> list.append(base, [canonical_script(value)])
    None -> base
  }
  let base = case region {
    Some(value) -> list.append(base, [canonical_region(value)])
    None -> base
  }
  let base = list.append(base, list.map(variants, string.lowercase))
  let extension_parts =
    extensions
    |> list.map(canonical_extension)
    |> list.flatten
  let base = list.append(base, extension_parts)
  let base = case privateuse {
    Some(values) -> {
      let private_parts = list.append(["x"], list.map(values, string.lowercase))
      list.append(base, private_parts)
    }
    None -> base
  }
  string.join(base, "-")
}

fn validate_language_subtag(language: String) -> Bool {
  let len = string.length(language)
  case len {
    len if len >= 2 && len <= 3 -> is_alpha_string(language)
    4 -> is_alpha_string(language)
    len if len >= 5 && len <= 8 -> is_alpha_string(language)
    _ -> False
  }
}

fn extract_extlangs(subtags: List(String)) -> #(List(String), List(String)) {
  extract_extlangs_loop(subtags, [])
}

fn extract_extlangs_loop(
  subtags: List(String),
  acc: List(String),
) -> #(List(String), List(String)) {
  case subtags {
    [candidate, ..rest] ->
      case
        list.length(acc) < 3
        && string.length(candidate) == 3
        && is_alpha_string(candidate)
      {
        True -> extract_extlangs_loop(rest, [candidate, ..acc])
        False -> #(list.reverse(acc), subtags)
      }
    [] -> #(list.reverse(acc), [])
  }
}

fn extract_script(subtags: List(String)) -> #(Option(String), List(String)) {
  case subtags {
    [script, ..rest] ->
      case string.length(script) == 4 && is_alpha_string(script) {
        True -> #(Some(script), rest)
        False -> #(None, subtags)
      }
    [] -> #(None, [])
  }
}

fn extract_region(subtags: List(String)) -> #(Option(String), List(String)) {
  case subtags {
    [region, ..rest] ->
      case string.length(region) {
        2 ->
          case is_alpha_string(region) {
            True -> #(Some(region), rest)
            False -> #(None, subtags)
          }
        3 ->
          case is_digit_string(region) {
            True -> #(Some(region), rest)
            False -> #(None, subtags)
          }
        _ -> #(None, subtags)
      }
    [] -> #(None, [])
  }
}

fn extract_variants(subtags: List(String)) -> #(List(String), List(String)) {
  extract_variants_loop(subtags, [])
}

fn extract_variants_loop(
  subtags: List(String),
  acc: List(String),
) -> #(List(String), List(String)) {
  case subtags {
    [variant, ..rest] ->
      case is_variant_subtag(variant) {
        True -> extract_variants_loop(rest, [variant, ..acc])
        False -> #(list.reverse(acc), subtags)
      }
    [] -> #(list.reverse(acc), [])
  }
}

fn extract_extensions(
  subtags: List(String),
) -> Result(#(List(List(String)), List(String)), Nil) {
  extract_extensions_loop(subtags, [])
}

fn extract_extensions_loop(
  subtags: List(String),
  acc: List(List(String)),
) -> Result(#(List(List(String)), List(String)), Nil) {
  case subtags {
    [singleton, ..rest] ->
      case is_extension_singleton(singleton) {
        True ->
          case extract_extension_subtags(rest, []) {
            Ok(#(subtags_list, remainder)) ->
              extract_extensions_loop(remainder, [
                [singleton, ..subtags_list],
                ..acc
              ])
            Error(_) -> Error(Nil)
          }
        False -> Ok(#(list.reverse(acc), subtags))
      }
    [] -> Ok(#(list.reverse(acc), []))
  }
}

fn extract_extension_subtags(
  subtags: List(String),
  acc: List(String),
) -> Result(#(List(String), List(String)), Nil) {
  case subtags {
    [subtag, ..rest] ->
      case is_extension_subtag(subtag) {
        True -> extract_extension_subtags(rest, [subtag, ..acc])
        False ->
          case acc {
            [] -> Error(Nil)
            _ -> Ok(#(list.reverse(acc), subtags))
          }
      }
    [] ->
      case acc {
        [] -> Error(Nil)
        _ -> Ok(#(list.reverse(acc), []))
      }
  }
}

fn extract_privateuse(
  subtags: List(String),
) -> Result(#(Option(List(String)), List(String)), Nil) {
  case subtags {
    ["x", ..rest] ->
      case rest {
        [] -> Error(Nil)
        _ ->
          case list.all(rest, is_privateuse_subtag) {
            True -> Ok(#(Some(rest), []))
            False -> Error(Nil)
          }
      }
    _ -> Ok(#(None, subtags))
  }
}

fn canonical_script(script: String) -> String {
  case string.to_graphemes(script) {
    [first, ..rest] ->
      string.uppercase(first) <> string.concat(list.map(rest, string.lowercase))
    [] -> script
  }
}

fn canonical_region(region: String) -> String {
  case string.length(region) {
    2 -> string.uppercase(region)
    _ -> region
  }
}

fn canonical_extension(extension: List(String)) -> List(String) {
  case extension {
    [singleton, ..rest] -> [
      string.lowercase(singleton),
      ..list.map(rest, string.lowercase)
    ]
    [] -> []
  }
}

fn is_alpha_string(value: String) -> Bool {
  string.to_graphemes(value)
  |> list.all(is_ascii_letter)
}

fn is_digit_string(value: String) -> Bool {
  string.to_graphemes(value)
  |> list.all(is_digit)
}

fn is_alphanum_string(value: String) -> Bool {
  string.to_graphemes(value)
  |> list.all(fn(char) { is_ascii_letter(char) || is_digit(char) })
}

fn is_variant_subtag(value: String) -> Bool {
  case string.length(value) {
    len if len >= 5 && len <= 8 -> is_alphanum_string(value)
    4 ->
      case string.to_graphemes(value) {
        [first, ..rest] ->
          is_digit(first)
          && list.all(rest, fn(char) { is_ascii_letter(char) || is_digit(char) })
        [] -> False
      }
    _ -> False
  }
}

fn is_extension_singleton(value: String) -> Bool {
  case string.to_graphemes(value) {
    [single] -> is_alphanum_string(single) && single != "x"
    _ -> False
  }
}

fn is_extension_subtag(value: String) -> Bool {
  let len = string.length(value)
  len >= 2 && len <= 8 && is_alphanum_string(value)
}

fn is_privateuse_subtag(value: String) -> Bool {
  let len = string.length(value)
  len >= 1 && len <= 8 && is_alphanum_string(value)
}

# Otzel

Otzel is an Elixir library for [Operational Transformation](https://en.wikipedia.org/wiki/Operational_transformation) (OT), providing a robust foundation for building collaborative real-time editing applications.

## What is Operational Transformation?

Operational Transformation is a technique for maintaining consistency in collaborative editing systems. When multiple users edit a shared document simultaneously, OT ensures that all users see the same final result regardless of the order in which edits are received.

Otzel implements the [Delta format](https://quilljs.com/docs/delta/), originally designed for the Quill rich text editor. Deltas represent both documents and changes to documents using a simple, composable format based on three operations: **insert**, **retain**, and **delete**.

## Features

- **Full OT Operations**: compose, transform, invert, and diff
- **Rich Text Support**: Attributes for formatting (bold, italic, colors, etc.)
- **Embedded Content**: Support for non-text embeds (images, videos, custom types)
- **Efficient String Handling**: Optimized IO-list based string representation
- **JSON Serialization**: Compatible with Quill Delta JSON format
- **No External Dependencies**: Pure Elixir with no Phoenix or Ecto requirements

## Installation

Add `otzel` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:otzel, "~> 0.4.0"}
  ]
end
```

## Quick Start

### Creating Operations

```elixir
# Create a document
doc = [Otzel.insert("Hello World")]

# Create a change that makes "World" bold
change = [Otzel.retain(6), Otzel.retain(5, %{"bold" => true})]

# Apply the change
new_doc = Otzel.compose(doc, change)
```

### The Three Operations

Otzel uses three fundamental operations:

#### Insert

Adds new content at the current position:

```elixir
# Insert plain text
Otzel.insert("Hello")

# Insert with formatting
Otzel.insert("Bold text", %{"bold" => true})

# Insert with multiple attributes
Otzel.insert("Styled", %{"bold" => true, "color" => "#ff0000"})
```

#### Retain

Keeps existing content, optionally modifying its attributes:

```elixir
# Keep 5 characters unchanged
Otzel.retain(5)

# Keep 5 characters and make them bold
Otzel.retain(5, %{"bold" => true})

# Remove bold formatting (set to nil)
Otzel.retain(5, %{"bold" => nil})
```

#### Delete

Removes content at the current position:

```elixir
# Delete 3 characters
Otzel.delete(3)
```

### Core Operations

#### Compose

Combines two deltas into a single delta that has the same effect as applying them sequentially:

```elixir
delta1 = [Otzel.insert("Hello")]
delta2 = [Otzel.retain(5), Otzel.insert(" World")]

# Result: [%Otzel.Op.Insert{content: "Hello World"}]
combined = Otzel.compose(delta1, delta2)
```

#### Transform

When two users make concurrent edits, transform adjusts one edit to account for the other:

```elixir
# User A inserts "A" at position 0
delta_a = [Otzel.insert("A")]

# User B inserts "B" at position 0
delta_b = [Otzel.insert("B")]

# Transform B against A (B came second)
# Result keeps B's insert after A's
transformed_b = Otzel.transform(delta_a, delta_b, :right)
```

The priority parameter (`:left` or `:right`) determines which edit "wins" when both insert at the same position.

#### Invert

Creates a delta that undoes the effect of another delta:

```elixir
doc = [Otzel.insert("Hello World")]
change = [Otzel.retain(6), Otzel.delete(5), Otzel.insert("Elixir")]

# Apply the change: "Hello Elixir"
new_doc = Otzel.compose(doc, change)

# Create the undo operation
undo = Otzel.invert(change, doc)

# Apply undo to get back to original
original = Otzel.compose(new_doc, undo)
```

#### Diff

Computes the delta needed to transform one document into another:

```elixir
doc1 = [Otzel.insert("Hello")]
doc2 = [Otzel.insert("Hello World")]

# Result: [Otzel.retain(5), Otzel.insert(" World")]
change = Otzel.diff(doc1, doc2)
```

### JSON Serialization

Otzel is compatible with the Quill Delta JSON format:

```elixir
# Create a delta
delta = [
  Otzel.insert("Hello "),
  Otzel.insert("World", %{"bold" => true})
]

# Convert to JSON string
json_string = JSON.encode!(delta)
# "[{\"insert\":\"Hello \"},{\"insert\":\"World\",\"attributes\":{\"bold\":true}}]"

# Parse from JSON
parsed = json_string |> JSON.decode!() |> Otzel.from_json()
```

### Working with Attributes

Attributes represent formatting applied to content:

```elixir
# Multiple attributes
Otzel.insert("Fancy", %{
  "bold" => true,
  "italic" => true,
  "color" => "#ff0000",
  "background" => "#ffff00"
})

# Attribute changes in retain
# This adds bold and removes italic
Otzel.retain(5, %{"bold" => true, "italic" => nil})
```

### Embedded Content

Otzel supports non-text content through the `Otzel.Content` protocol:

```elixir
# The library includes Otzel.Content.Ot for nested OT content
# You can implement the protocol for custom embeds like images:

defmodule MyApp.ImageEmbed do
  use Otzel.Content, atomic: true

  defstruct [:url, :width, :height]

  # Required callbacks for OT operations
  def compose(_, _), do: raise "not implemented"
  def transform(_, _, _), do: raise "not implemented"
  def invert(_, _), do: raise "not implemented"
end
```

#### Checking Content Type

Use `Otzel.Content.embed?/1` to check if content is an embedded type vs string-like:

```elixir
string_content = %Otzel.Content.Iomemo{s: "hello", l: 5}
embed_content = %Otzel.Content.Ot{transform: [Otzel.insert("nested")]}

Otzel.Content.embed?(string_content)  # => false
Otzel.Content.embed?(embed_content)   # => true
```

#### JSON Deserialization with Custom Embeds

When deserializing JSON that contains embedded content, use the `:embed_encoder` option to convert JSON maps back to your embed structs. The encoder can be either an anonymous function or a `{module, function}` tuple:

```elixir
# Option 1: Anonymous function (useful for simple cases)
encoder = fn
  %{"image" => url} -> %MyApp.ImageEmbed{url: url}
  %{"embed" => ops} -> %Otzel.Content.Ot{transform: Otzel.from_json(ops)}
  other -> other
end

json = [%{"insert" => %{"image" => "photo.jpg"}}]
Otzel.from_json(json, embed_encoder: encoder)

# Option 2: Module function tuple (useful for complex or reusable encoders)
defmodule MyApp.EmbedEncoder do
  def decode(%{"image" => url}) do
    %MyApp.ImageEmbed{url: url}
  end

  def decode(%{"embed" => ops}) when is_list(ops) do
    %Otzel.Content.Ot{transform: Otzel.from_json(ops)}
  end

  def decode(other), do: other  # Pass through unknown content
end

Otzel.from_json(json, embed_encoder: {MyApp.EmbedEncoder, :decode})

# Configure globally in config.exs (supports both formats)
config :otzel, :embed_encoder, {MyApp.EmbedEncoder, :decode}
# or
config :otzel, :embed_encoder, &MyApp.EmbedEncoder.decode/1
```

#### Error Handling

`Otzel.ContentError` is raised when there's a type mismatch between content types:

```elixir
# This raises ContentError - can't invert an embedded retain against string content
delta = [Otzel.retain(%Otzel.Content.Ot{transform: [Otzel.insert("a")]})]
base = [Otzel.insert("a")]

Otzel.invert(delta, base)
# ** (Otzel.ContentError) cannot retain a string with embedded content
```

## Architecture

### Module Overview

- **`Otzel`** - Main module with all core OT operations
- **`Otzel.Op`** - Protocol for operations (Insert, Retain, Delete)
- **`Otzel.Op.Insert`** - Insert operation struct
- **`Otzel.Op.Retain`** - Retain operation struct
- **`Otzel.Op.Delete`** - Delete operation struct
- **`Otzel.Content`** - Protocol for content types
- **`Otzel.Content.Iomemo`** - Efficient IO-list based string representation
- **`Otzel.Content.Ot`** - Nested OT content for embeds
- **`Otzel.Attrs`** - Attribute manipulation utilities
- **`Otzel.ContentError`** - Exception for content type mismatches

### String Representation

By default, Otzel uses `Otzel.Content.Iomemo` for string content, which stores strings as IO-lists with precomputed lengths. This provides efficient splitting and concatenation operations common in OT workloads.

You can configure a different string module:

```elixir
# In config.exs
config :otzel, :string_module, String

# Or per-operation
Otzel.insert("Hello", nil, String)
```

## OT Invariants

Otzel maintains the standard OT invariants:

1. **Compose associativity**: `compose(compose(a, b), c) == compose(a, compose(b, c))`

2. **Transform convergence (TP1)**: For concurrent operations A and B:
   ```
   compose(A, transform(A, B, :right)) == compose(B, transform(B, A, :left))
   ```

3. **Invert correctness**: For document D and change C:
   ```
   compose(compose(D, C), invert(C, D)) == D
   ```

## Performance

Benchmarks comparing Otzel against the [Delta](https://hex.pm/packages/delta) Elixir library.

### High-Complexity (Fragmented Documents)

Randomized OT operations representing highly fragmented documents with many small operations.

| Operation | Otzel | Delta | Speedup | Memory |
|-----------|-------|-------|---------|--------|
| diff | 526 μs | 676 μs | **1.3x** | 18% less |
| compose | 33 ms | 2,046 ms | **61x** | 20x less |
| invert | 27 ms | 8,849 ms | **331x** | 103x less |

### Low-Complexity (Typical Editing)

**Simple:** Single ~10KB document with minimal changes

| Operation | Otzel | Delta | Speedup |
|-----------|-------|-------|---------|
| diff | 4.2 μs | 988 μs | **235x** |
| compose | 1.7 μs | 12.2 μs | **7x** |
| invert | 1.9 μs | 14.4 μs | **7.5x** |

**Typing:** Sequential character-by-character edits

| Operation | Otzel | Delta | Speedup |
|-----------|-------|-------|---------|
| diff | 204 μs | 15.7 ms | **77x** |
| compose | 20.7 μs | 287 μs | **14x** |
| invert | 17.8 μs | 37.9 μs | **2x** |

### Detailed Results

See [PERFORMANCE.md](PERFORMANCE.md) for full benchmark data across all string representations.

**Test Environment:** Linux, AMD Ryzen 7 7840U, 16 cores, Elixir 1.18.4, Erlang 28.1 with JIT

### Why Otzel is Faster

1. **IO-list string representation** (`Iomemo`): Structural sharing during split/concatenate avoids copying
2. **Optimized diff**: Single-pass serialization with embed detection, skips reconstruction for text-only documents
3. **Efficient iteration**: Avoids intermediate allocations in compose/transform loops

### Understanding the Speedup Variation

The diff speedup varies dramatically: **1.3x** for high-complexity vs **235x** for simple documents. This reveals two different performance factors:

- **High-complexity (fragmented)**: Many small strings amortize per-string overhead. The 1.3x speedup reflects the core diff algorithm efficiency.
- **Low-complexity (large strings)**: Delta's overhead scales with string length (codepoint conversion, intermediate allocations). On a 10KB contiguous string, this overhead dominates—Delta takes ~1ms while Otzel takes ~4μs.

In other words, high-complexity benchmarks measure algorithmic efficiency, while low-complexity benchmarks expose string handling overhead.

## Comparison with Other Libraries

Otzel implements the same Delta format as [quill-delta](https://github.com/quilljs/delta).

| Feature | Otzel | Delta (Elixir) | quill-delta (JS) |
|---------|-------|----------------|------------------|
| Compose | ✓ | ✓ | ✓ |
| Transform | ✓ | ✓ | ✓ |
| Invert | ✓ | ✓ | ✓ |
| Diff | ✓ | ✓ | ✓ |
| Custom embeds | ✓ (protocol-based) | ✓ | ✓ |
| Nested OT embeds | ✓ (diffable) | Limited | Plugin |
| Mixed embed+text diff | ✓ | ✗ | Plugin ([quill-delta-enhanced](https://github.com/SilentTiger/quill-delta-enhanced)) |
| Semantic cleanup | ✓ | ✓ | ✓ |
| JSON compatible | ✓ | ✓ | ✓ |

Otzel's mixed content diff uses NULL character serialization with iterator-based reconstruction, following the quill-delta-enhanced approach.

### When to Use Otzel

- **High-throughput collaborative editing** with many concurrent operations
- **Complex documents** with mixed text and embeds
- **Nested OT structures** requiring recursive diffing
- **Memory-constrained environments** where allocation efficiency matters

## Testing

```bash
mix test
```

The test suite includes property-based tests that verify OT invariants across randomly generated operations.

## License

MIT License. See [LICENSE](LICENSE) for details.

## Acknowledgments

- Inspired by the [Quill Delta](https://quilljs.com/docs/delta/) format
- Based on operational transformation theory from [OT FAQ](https://www3.ntu.edu.sg/home/czsun/projects/otfaq/)

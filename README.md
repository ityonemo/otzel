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
    {:otzel, "~> 0.1.0"}
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

# Convert to JSON-compatible format
json = Otzel.json(delta)
# [%{"insert" => "Hello "}, %{"insert" => "World", "attributes" => %{"bold" => true}}]

# Parse from JSON
parsed = Otzel.from_json(json)
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

  # Implement required callbacks...
end
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

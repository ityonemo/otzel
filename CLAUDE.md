# Otzel Development Guide

## Project Overview

Otzel is an Elixir library for Operational Transformation (OT). It has no Phoenix or Ecto dependencies.

## Running Tests

```bash
mix test
```

## Tidewave MCP

This project uses Tidewave for enhanced AI-assisted development. Start it with:

```bash
mix tidewave
```

Then configure your MCP client to connect to `http://localhost:4000/tidewave/mcp`.

For Claude Code:
```bash
claude mcp add tidewave-otzel --transport http http://localhost:4000/tidewave/mcp
```

### Available Tidewave Tools

Always prefer Tidewave tools over shell commands for Elixir-specific tasks:

#### `project_eval`
Evaluate Elixir code in the context of the project. Use this instead of `mix run -e` or shell commands. IEx helpers are available (e.g., `h Enum.map/2`, `exports(ModuleName)`).

```
# Test a function
Otzel.compose([Otzel.insert("hello")], [Otzel.retain(5), Otzel.insert("!")])

# Check module exports
exports(Otzel.Content.Iomemo)
```

#### `get_docs`
Retrieve documentation for modules and functions. Works for project code and dependencies.

```
# Get docs for a module
get_docs Otzel.Content.Iomemo

# Get docs for a specific function
get_docs Otzel.Content.Iomemo.diff/2
```

#### `get_source_location`
Find the source file and line number for a module or function. Preferred over grepping when you know the target.

```
# Find where a module is defined
get_source_location Otzel.Content.Iomemo

# Find a specific function
get_source_location Otzel.Content.Iomemo.diff/2

# Find a dependency's source
get_source_location dep:diffy
```

#### `get_logs`
Inspect application logs for debugging. Useful for tracing errors during development.

#### `search_package_docs`
Search Hex documentation across the project's dependencies.

```
# Search for streaming-related docs
search_package_docs "stream"
```

### Recompiling in Tidewave

If you modify source files and need Tidewave to pick up the changes, use `project_eval` with:

```elixir
IEx.Helpers.recompile()
```

### Best Practices

1. Use `project_eval` to test code snippets instead of writing temporary test files
2. Use `get_source_location` to navigate to definitions instead of grepping
3. Use `get_docs` to understand module/function behavior before modifying code
4. Use `get_logs` when debugging runtime errors
5. Use `IEx.Helpers.recompile()` in `project_eval` after modifying source files

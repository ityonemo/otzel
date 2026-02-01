use Protoss

defprotocol Otzel.Content do
  @moduledoc """
  Protocol for content types that can be stored in delta operations.

  The Content protocol defines how different content types behave within
  the OT system. By default, strings are supported, but you can implement
  this protocol for custom embedded content types like images, videos,
  or nested documents.

  ## Built-in Implementations

  - `BitString` - Standard Elixir strings
  - `Otzel.Content.Iomemo` - Efficient IO-list based strings (default)
  - `Otzel.Content.Ot` - Nested OT documents

  ## Implementing Custom Content

  For simple atomic embeds (size 1, cannot be split), use the `atomic: true` option:

      defmodule MyApp.ImageEmbed do
        use Otzel.Content, atomic: true

        defstruct [:url, :width, :height]

        def invert(_, _), do: raise "not implemented"
        def compose(_, _), do: raise "not implemented"
        def transform(_, _, _), do: raise "not implemented"
      end

  The `atomic: true` option automatically implements:
  - `size/1` - Returns 1
  - `take/2` - Returns the whole content
  - `merge_into/2` - Returns nil (cannot merge)
  - `as_binary/1` - Returns nil
  - `embed?/1` - Returns true (is embedded content)
  - `diff/2` - Returns empty list for equal content, or delete+insert for different content

  ## Checking Content Type

  Use `embed?/1` to check if content is an embedded type (returns `true`) or
  string-like (returns `false`):

      Otzel.Content.embed?(string_content)  # => false
      Otzel.Content.embed?(embed_content)   # => true

  """

  @doc "Inverts content changes for undo operations"
  @spec invert(t, t) :: t
  def invert(content1, content2)

  @doc "Composes two content values"
  @spec compose(t, t) :: t
  def compose(content1, content2)

  @doc "Transforms content for concurrent edits"
  @spec transform(t, t, Otzel.priority()) :: {t | nil, t, t}
  def transform(content1, content2, priority)

  @doc "Attempts to merge adjacent content values"
  @spec merge_into(t, t) :: t | nil
  def merge_into(content1, content2)

  @doc "Splits content at the given position"
  @spec take(t, non_neg_integer) :: {t, t | nil}
  def take(content, count)

  @doc "Returns the size (character count) of the content"
  @spec size(t) :: non_neg_integer
  def size(content)

  @doc "Computes the diff between two content values"
  @spec diff(t, t) :: [insert: t, equals: t, delete: t]
  def diff(src, dst)

  @doc "Converts content to a binary string, or nil if not applicable"
  @spec as_binary(t) :: binary | nil
  def as_binary(content)

  @doc "Converts content to an iodata, or <<0>> if it's an embed"
  @spec as_iodata(t, embed_value :: binary) :: iodata
  def as_iodata(content, embed_value)

  @doc "Returns true if the content is an embedded type (not string-like)"
  @spec embed?(t) :: boolean
  def embed?(content)
after
  alias Otzel.Op.Insert
  alias Otzel.Op.Retain

  defmacro __using__(opts) do
    if opts[:atomic] do
      quote do
        def size(_), do: 1
        def take(op, _count), do: {op, nil}
        def merge_into(_, _), do: nil
        def as_binary(_), do: nil
        def embed?(_), do: true
        def concatenate([single]), do: single

        def as_iodata(_, embed_value), do: embed_value

        def diff(a, b) when a == b, do: []

        def diff(_a, b) do
          [%Otzel.Op.Delete{count: 1}, %Otzel.Op.Insert{content: b}]
        end

        defoverridable diff: 2
      end
    end
  end

  @doc "Converts content to an iodata, or <<0>> if it's an embed"
  def as_iodata(content), do: as_iodata(content, <<0>>)

  @doc """
  Extracts the content from an operation.

  For Insert operations, returns the content being inserted.
  For Retain operations, returns the target (count or embedded content).
  """
  def from(%Retain{} = op), do: op.target
  def from(%Insert{} = op), do: op.content

  @doc """
  Remaps Insert operations to use a specific string module.

  Converts the content of each Insert operation to the given module's
  representation (e.g., `String` or `Otzel.Content.Iomemo`).
  """
  def remap_inserts(ops, module), do: Enum.map(ops, &remap_insert(&1, module))

  defp remap_insert(%Insert{} = insert, String) do
    if binary = as_binary(insert.content) do
      %{insert | content: binary}
    else
      insert
    end
  end

  defp remap_insert(%Insert{} = insert, module) do
    if binary = as_binary(insert.content) do
      %{insert | content: module.new(binary)}
    else
      insert
    end
  end

  defp remap_insert(op, _module), do: op

  @doc """
  Concatenates a list of content values into a single content value.

  Delegates to the appropriate content module's `concatenate/1` function
  based on the type of the first element.
  """
  def concatenate(list = [%module{} | _]), do: module.concatenate(list)
  def concatenate(list = [head | _]) when is_binary(head), do: IO.iodata_to_binary(list)
end

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
        def diff(_, _), do: raise "not implemented"
      end

  The `atomic: true` option automatically implements:
  - `size/1` - Returns 1
  - `take/2` - Returns the whole content
  - `merge_into/2` - Returns nil (cannot merge)
  - `as_binary/1` - Returns nil

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
after
  alias Otzel.Op.Insert
  alias Otzel.Op.Retain
  alias Otzel.Attr

  defmacro __using__(opts) do
    if opts[:atomic] do
      quote do
        def size(_), do: 1
        def take(op, _count), do: {op, nil}
        def merge_into(_, _), do: nil
        def as_binary(_), do: nil
      end
    end
  end

  @callback diff(t, t, Attr.t(), Attr.t()) :: Otzel.t() | nil
  @optional_callbacks diff: 4

  def from(%Retain{} = op), do: op.target
  def from(%Insert{} = op), do: op.content

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

  def concatenate(list = [%module{} | _]), do: module.concatenate(list)
  def concatenate(list = [head | _]) when is_binary(head), do: IO.iodata_to_binary(list)
end

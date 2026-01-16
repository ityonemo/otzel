defmodule Otzel.Content.Ot do
  @moduledoc """
  Content type for nested OT documents (embedded deltas).

  This allows embedding one OT document inside another, enabling
  hierarchical document structures where inner documents can be
  collaboratively edited independently.

  ## Use Case

  Useful for complex documents with nested editable regions, such as:
  - Tables with editable cells
  - Collapsible sections
  - Embedded notes or comments

  ## Structure

  - `:transform` - The nested delta (list of operations)

  ## Example

      # Create an embedded document
      inner = [Otzel.insert("Nested content")]
      embed = %Otzel.Content.Ot{transform: inner}

      # Insert it into an outer document
      outer = [Otzel.insert(embed)]

  """

  use Otzel.Content, atomic: true

  alias Otzel.Op.Retain

  defstruct transform: []

  def compose(left, right = %__MODULE__{}) do
    %__MODULE__{transform: Otzel.compose(left.transform, right.transform)}
  end

  def transform(left, right = %__MODULE__{}, priority) do
    %__MODULE__{transform: Otzel.transform(left.transform, right.transform, priority)}
  end

  def invert(left, right = %__MODULE__{}) do
    %__MODULE__{transform: Otzel.invert(left.transform, right.transform)}
  end

  def diff(src, %__MODULE__{} = dst) do
    case Otzel.diff(src.transform, dst.transform) do
      [] ->
        []

      inner_diff ->
        [
          %Retain{
            target: %__MODULE__{transform: inner_diff},
            attrs: nil
          }
        ]
    end
  end

  # Different content types - fall back to delete + insert
  def diff(_src, dst) do
    [%Otzel.Op.Delete{count: 1}, %Otzel.Op.Insert{content: dst}]
  end

  defimpl JSON.Encoder do
    def encode(ot, opts) do
      JSON.Encoder.encode(%{"embed" => ot.transform}, opts)
    end
  end
end

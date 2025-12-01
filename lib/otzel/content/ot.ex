defmodule Otzel.Content.Ot do
  use Otzel.Content, atomic: true

  alias Otzel.Op.Retain
  alias Otzel.Attrs

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

  def diff(%{transform: src}, %{transform: dst}, src_attr, dst_attr) do
    %Retain{
      target: %__MODULE__{transform: Otzel.diff(src, dst)},
      attrs: Attrs.diff(src_attr, dst_attr)
    }
  end

  defimpl JSON.Encoder do
    def encode(ot, opts) do
      JSON.Encoder.encode(%{"embed" => ot.transform}, opts)
    end
  end
end

defmodule OtzelTest.Content.Integer do
  use Otzel.Content, atomic: true

  @enforce_keys [:value]
  defstruct @enforce_keys

  def new(value), do: %__MODULE__{value: value}

  def transform(_, _, _), do: raise("not implemented")

  def invert(_, _), do: raise("not implemented")

  def compose(_, _), do: raise("not implemented")
end

defmodule OtzelTest.Content.Image do
  use Otzel.Content, atomic: true

  @enforce_keys [:url, :alt]
  defstruct @enforce_keys

  def new(url, alt \\ nil), do: %__MODULE__{url: url, alt: alt}

  def transform(_, _, _), do: raise("not implemented")

  def invert(_, _), do: raise("not implemented")

  def compose(_, _), do: raise("not implemented")
end

defmodule OtzelTest.Content.Quote do
  use Otzel.Content, atomic: true

  alias Otzel.Attrs
  alias Otzel.Op.Retain
  alias Otzel.Op.Delete

  @enforce_keys [:text]
  defstruct @enforce_keys

  def diff(%{text: src}, %{text: dst}, src_attr, dst_attr) do
    size = Otzel.size(src)

    case Otzel.diff(src, dst) do
      [%Delete{count: ^size} | _] ->
        nil

      diff ->
        %Retain{
          target: %__MODULE__{text: diff},
          attrs: Attrs.diff(src_attr, dst_attr)
        }
    end
  end

  def new(text), do: %__MODULE__{text: List.wrap(text)}

  def transform(_, _, _), do: raise("not implemented")

  def invert(_, _), do: raise("not implemented")

  def compose(_, _), do: raise("not implemented")
end

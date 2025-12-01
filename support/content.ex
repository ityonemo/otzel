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

  @enforce_keys [:text]
  defstruct @enforce_keys

  def new(text), do: %__MODULE__{text: List.wrap(text)}

  def transform(_, _, _), do: raise("not implemented")

  def invert(_, _), do: raise("not implemented")

  def compose(_, _), do: raise("not implemented")
end

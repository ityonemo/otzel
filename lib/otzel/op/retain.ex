defmodule Otzel.Op.Retain do
  use Otzel.Op

  @enforce_keys [:target]
  defstruct @enforce_keys ++ [:attrs]

  alias Otzel.Attrs
  alias Otzel.Content

  @type t :: %__MODULE__{
          target: pos_integer() | Content.t(),
          attrs: Attrs.t()
        }

  def merge_into(%{target: c1, attrs: attrs}, %__MODULE__{target: c2, attrs: attrs})
      when is_integer(c1) and is_integer(c2) do
    %__MODULE__{
      target: c1 + c2,
      attrs: attrs
    }
  end

  def merge_into(_, _), do: nil

  def size(%{target: target}) when is_integer(target), do: target
  def size(%{target: target}), do: Content.size(target)

  def take(retain, count) when not is_integer(retain.target) do
    case Content.take(retain.target, count) do
      {taken, nil} ->
        {%{retain | target: taken}, nil}

      {taken, rest} ->
        {%{retain | target: taken}, %{retain | target: rest}}
    end
  end

  def take(retain, count) when count === retain.target, do: {retain, nil}

  def take(retain, count) when count < retain.target,
    do: {%{retain | target: count}, %{retain | target: retain.target - count}}

  def from_json(%{"retain" => target} = json) do
    %__MODULE__{
      target: target,
      attrs: Map.get(json, "attributes")
    }
  end
end

require Otzel.Op

for json_encoder <- Otzel.Op.json_encoders() do
  defimpl json_encoder, for: Otzel.Op.Retain do
    def encode(%{target: content, attrs: nil}, opts) do
      unquote(json_encoder).encode(%{"retain" => content}, opts)
    end

    def encode(%{target: content, attrs: attrs}, opts) do
      unquote(json_encoder).encode(%{"retain" => content, "attributes" => attrs}, opts)
    end
  end
end

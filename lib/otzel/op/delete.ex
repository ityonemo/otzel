defmodule Otzel.Op.Delete do
  use Otzel.Op

  @enforce_keys [:count]
  defstruct @enforce_keys

  @type t :: %__MODULE__{count: pos_integer()}

  def merge_into(%{count: c1}, %__MODULE__{count: c2}) do
    %__MODULE__{count: c1 + c2}
  end

  def merge_into(_, _), do: nil

  def size(%{count: count}), do: count

  def take(delete, count) when count === delete.count, do: {delete, nil}

  def take(delete, count) when count < delete.count,
    do: {%{delete | count: count}, %{delete | count: delete.count - count}}

  def from_json(%{"delete" => count}) do
    %__MODULE__{count: count}
  end
end

require Otzel.Op

for json_encoder <- Otzel.Op.json_encoders() do
  defimpl json_encoder, for: Otzel.Op.Delete do
    def encode(%{count: count}, opts) do
      unquote(json_encoder).encode(%{"delete" => count}, opts)
    end
  end
end

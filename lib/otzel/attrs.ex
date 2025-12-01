defmodule Otzel.Attrs do
  @type t :: %{optional(String.t()) => any} | nil

  @spec compose(t, t, keep_nils :: boolean) :: t
  def compose(a, b, keep_nils \\ false) do
    case {a, b} do
      {nil, _} ->
        b

      {_, nil} ->
        a

      _ ->
        Map.merge(a, b)
    end
    |> cleanup(keep_nils)
    |> nilify()
  end

  def cleanup(map, false) when is_map(map) do
    for {k, v} <- map, v != nil, into: %{}, do: {k, v}
  end

  def cleanup(other, _), do: other

  defp nilify(map) when map_size(map) == 0, do: nil
  defp nilify(map), do: map

  @spec invert(t, t) :: t
  def invert(nil, base), do: invert(%{}, base)
  def invert(attr, nil), do: invert(attr, %{})

  def invert(attr, base) do
    inverted =
      for {k, v} <- base, match?(%{^k => v2} when v2 != v, attr), into: %{}, do: {k, v}

    map =
      for {k, v} <- attr,
          not (Map.has_key?(base, k) || is_nil(v)),
          into: inverted,
          do: {k, nil}

    nilify(map)
  end

  @spec diff(t, t) :: t
  def diff(same, same), do: nil
  def diff(nil, base), do: base

  def diff(left, nil) do
    for {k, _} <- left, into: %{}, do: {k, nil}
  end

  def diff(left, right) do
    left_diff =
      for k <- Map.keys(left), into: %{} do
        case Map.fetch(right, k) do
          {:ok, v2} -> {k, v2}
          _ -> {k, nil}
        end
      end

    for {k, v} <- right, not is_map_key(left, k), into: left_diff do
      {k, v}
    end
  end

  @spec transform(t, t, Otzel.priority()) :: t
  def transform(from, into, priority)

  def transform(nil, b, _), do: b
  def transform(_, nil, _), do: nil
  def transform(_, b, :right), do: b

  def transform(a, b, _) do
    nilify(for {k, v} <- b, not is_map_key(a, k), into: %{}, do: {k, v})
  end
end

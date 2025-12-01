defmodule Otzel.Attrs do
  @moduledoc """
  Utilities for working with operation attributes.

  Attributes are maps of formatting properties applied to content, such as
  `%{"bold" => true, "color" => "#ff0000"}`. They are used with Insert and
  Retain operations to style text.

  ## Attribute Values

  - Any truthy value applies the attribute
  - `nil` removes the attribute
  - Missing keys leave the attribute unchanged

  ## Functions

  - `compose/3` - Combines attributes from sequential operations
  - `transform/3` - Adjusts attributes for concurrent operations
  - `invert/2` - Creates attributes that undo a change
  - `diff/2` - Computes the difference between two attribute sets

  ## Examples

      # Compose: second operation wins
      Otzel.Attrs.compose(%{"bold" => true}, %{"italic" => true})
      #=> %{"bold" => true, "italic" => true}

      # Diff: compute changes needed
      Otzel.Attrs.diff(%{"bold" => true}, %{"italic" => true})
      #=> %{"bold" => nil, "italic" => true}

  """

  @typedoc """
  Attributes are a map of string keys to values, or nil.

  A nil value for a key indicates the attribute should be removed.
  A nil attrs map means no attributes are set.
  """
  @type t :: %{optional(String.t()) => any} | nil

  @doc """
  Composes two attribute maps, with the second map taking precedence.

  Used when applying sequential operations - the later operation's
  attributes override earlier ones.

  ## Options

  - `keep_nils` - When true, preserves nil values in the result (default: false)

  ## Examples

      iex> Otzel.Attrs.compose(%{"bold" => true}, %{"italic" => true})
      %{"bold" => true, "italic" => true}

      iex> Otzel.Attrs.compose(%{"bold" => true}, %{"bold" => nil})
      nil

  """
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

  @doc """
  Computes attributes that would undo a change.

  Given the attributes that were applied and the original base attributes,
  returns attributes that would restore the original state.

  ## Examples

      iex> Otzel.Attrs.invert(%{"bold" => true}, nil)
      %{"bold" => nil}

      iex> Otzel.Attrs.invert(%{"bold" => nil}, %{"bold" => true})
      %{"bold" => true}

  """
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

  @doc """
  Computes the difference between two attribute maps.

  Returns attributes that, when applied to `left`, would produce `right`.
  Keys present in `left` but not `right` are set to `nil` (removal).

  ## Examples

      iex> Otzel.Attrs.diff(%{"bold" => true}, %{"bold" => true})
      nil

      iex> Otzel.Attrs.diff(%{"bold" => true}, %{"italic" => true})
      %{"bold" => nil, "italic" => true}

      iex> Otzel.Attrs.diff(nil, %{"bold" => true})
      %{"bold" => true}

  """
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

  @doc """
  Transforms attributes for concurrent operations.

  When two operations modify the same content concurrently, this determines
  which attributes take effect based on priority.

  ## Priority

  - `:right` - The `into` attributes win (default)
  - `:left` - Only `into` attributes not in `from` are kept

  ## Examples

      iex> Otzel.Attrs.transform(%{"bold" => true}, %{"italic" => true}, :right)
      %{"italic" => true}

      iex> Otzel.Attrs.transform(%{"bold" => true}, %{"bold" => false}, :left)
      nil

  """
  @spec transform(t, t, Otzel.priority()) :: t
  def transform(from, into, priority)

  def transform(nil, b, _), do: b
  def transform(_, nil, _), do: nil
  def transform(_, b, :right), do: b

  def transform(a, b, _) do
    nilify(for {k, v} <- b, not is_map_key(a, k), into: %{}, do: {k, v})
  end
end

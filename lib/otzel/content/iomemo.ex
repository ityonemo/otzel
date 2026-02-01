defmodule Otzel.Content.Iomemo do
  @moduledoc """
  An efficient IO-list based string representation for OT operations.

  Iomemo (IO-list with memoized length) stores strings as nested IO-lists
  along with precomputed length information. This provides O(1) size lookups
  and efficient splitting/concatenation operations that are common in OT.

  ## Why IO-lists?

  In collaborative editing, strings are frequently split and concatenated.
  Standard Elixir strings require copying the entire string for these
  operations. IO-lists allow structural sharing, making these operations
  much more efficient for large documents.

  ## Structure

  - `:s` - The string data as an IO-list
  - `:l` - Memoized length information matching the IO-list structure

  ## Usage

  Iomemo is the default string module. Strings are automatically converted:

      # This creates an Iomemo internally
      Otzel.insert("Hello World")

  You can also create directly:

      Otzel.Content.Iomemo.new("Hello World")

  ## Configuration

  To use standard strings instead:

      config :otzel, :string_module, String

  """

  use Otzel.Content

  @enforce_keys ~w[s l]a
  defstruct @enforce_keys

  defp codepoint_split_at(string, count) do
    codepoints = String.codepoints(string)

    {Enum.take(codepoints, count) |> IO.iodata_to_binary(),
     Enum.drop(codepoints, count) |> IO.iodata_to_binary()}
  end

  @type len_list ::
          maybe_improper_list(non_neg_integer | {non_neg_integer, len_list}, non_neg_integer)
  @type str_list :: maybe_improper_list(String.t() | str_list, String.t())
  @type t :: %__MODULE__{
          s: str_list | String.t(),
          l: len_list | non_neg_integer
        }

  @doc """
  Creates a new Iomemo from a string or IO-list.

  ## Examples

      iex> Otzel.Content.Iomemo.new("Hello")
      %Otzel.Content.Iomemo{s: "Hello", l: 5}

  """
  def new(str), do: %__MODULE__{s: str, l: len_of(str)}

  def compose(left, right = %__MODULE__{}) do
    merge_into(right, left)
  end

  def merge_into(left, right) do
    case left.l do
      {sz_left, l_left} ->
        %__MODULE__{s: [right.s | left.s], l: {tlen(right.l) + sz_left, [right.l | l_left]}}

      _ ->
        %__MODULE__{s: [right.s | left.s], l: {tlen(right.l) + left.l, [right.l | left.l]}}
    end
  end

  def size(%{l: l}), do: tlen(l)

  defguardp oversized(ldata, count)
            when (is_tuple(ldata) and elem(ldata, 0) <= count) or ldata <= count

  def take(%{l: l} = iomemo, count) when oversized(l, count), do: {iomemo, nil}

  def take(content, count) do
    {prefix, affix} = iodata_split(content.s, content.l, count)
    {to_struct(prefix), to_struct(affix)}
  end

  defp to_struct({str, len}), do: %__MODULE__{s: str, l: len}

  defp iodata_split([head | rest], {len, [lhead | lrest]}, count) do
    case tlen(lhead) do
      llen when llen > count ->
        {{sprefix, lprefix}, {saffix, laffix}} = iodata_split(head, lhead, count)
        {{sprefix, lprefix}, {[saffix | rest], {len - count, [laffix | lrest]}}}

      llen when llen == count ->
        if is_list(lrest) do
          {{head, lhead}, {rest, {len - count, lrest}}}
        else
          {{head, lhead}, {rest, lrest}}
        end

      llen ->
        # llen < count
        if is_list(lrest) do
          case iodata_split(rest, {len - llen, lrest}, count - llen) do
            {{sprefix, {_, lprefix}}, {saffix, laffix}} ->
              {{[head | sprefix], {count, [lhead | lprefix]}}, {saffix, laffix}}

            {{sprefix, lprefix}, {saffix, laffix}} ->
              {{[head | sprefix], {count, [lhead | lprefix]}}, {saffix, laffix}}
          end
        else
          {{sprefix, lprefix}, {saffix, laffix}} = iodata_split(rest, lrest, count - llen)
          {{[head | sprefix], {count, [lhead | lprefix]}}, {saffix, laffix}}
        end
    end
  end

  defp iodata_split(binary, len, count) when is_binary(binary) do
    {a, b} = codepoint_split_at(binary, count)
    {{a, count}, {b, len - count}}
  end

  def transform(_, _, _), do: raise("unimplemented")

  def invert(_, _), do: raise("unimplemented")

  def concatenate(list) do
    {rev_str, l, rev_ls} =
      Enum.reduce(list, {[], 0, []}, fn
        %__MODULE__{s: s, l: l}, {acc_s, acc_l, acc_ls} ->
          {[s | acc_s], acc_l + tlen(l), [l | acc_ls]}
      end)

    %__MODULE__{s: Enum.reverse(rev_str), l: {l, Enum.reverse(rev_ls)}}
  end

  defp len_of(binary) when is_binary(binary), do: Otzel._codepoints(binary)

  defp len_of(list), do: len_of_list(list, 0)

  defp len_of_list([head | rest], _so_far) do
    head = len_of(head)
    {count, list} = len_of_list(rest, 0)
    {count + count_of(head), [head | list]}
  end

  defp len_of_list([], _so_far), do: {0, []}

  defp len_of_list(head, _so_far) do
    head
    |> len_of
    |> then(&{count_of(&1), &1})
  end

  defp count_of(integer) when is_integer(integer), do: integer
  defp count_of({integer, _list}), do: integer

  def as_binary(iodata), do: IO.iodata_to_binary(iodata.s)
  def as_iodata(iodata, _), do: iodata.s
  def embed?(_), do: false

  @doc """
  Checks if the Iomemo's cached length is consistent with its content.

  Returns `true` if the memoized length matches the actual content length.
  Useful for debugging and validation.
  """
  def well_formed?(iodata), do: consistent?(iodata.s, iodata.l)

  defp consistent?(string, length) when is_binary(string) do
    Otzel._codepoints(string) == length
  end

  defp consistent?([str_head | str_tail] = iodata, {size, [len_head | len_tail]}) do
    size_consistent? = Otzel._codepoints(IO.iodata_to_binary(iodata)) == size

    head_consistent? = consistent?(str_head, len_head)

    tail_consistent? =
      case len_tail do
        len_tail when is_list(len_tail) ->
          consistent?(str_tail, {size - tlen(len_head), len_tail})

        _ ->
          consistent?(str_tail, size - tlen(len_head))
      end

    head_consistent? and tail_consistent? and size_consistent?
  end

  def diff(a, b) do
    a_str = as_binary(a)
    b_str = as_binary(b)

    Otzel.Diff.diff(a_str, b_str, __MODULE__)
  end

  defp tlen({len, _}), do: len
  defp tlen(len) when is_integer(len), do: len

  defimpl JSON.Encoder do
    def encode(iodata, opts) do
      iodata.s
      |> IO.iodata_to_binary()
      |> JSON.Encoder.encode(opts)
    end
  end

  defimpl String.Chars do
    def to_string(iodata), do: IO.iodata_to_binary(iodata.s)
  end
end

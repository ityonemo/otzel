defmodule Otzel.Content.Iomemo do
  use Otzel.Content

  alias Otzel.Op.Insert

  @enforce_keys ~w[s l]a
  defstruct @enforce_keys

  # Use codepoints instead of graphemes for consistent counting
  defp codepoint_length(string), do: length(String.codepoints(string))

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
  defp to_struct(nil), do: nil

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

  def take(content, _count), do: {content, nil}

  def transform(_, _, _), do: raise("unimplemented")

  def invert(_, _), do: raise("unimplemented")

  def concatenate(list) do
    {rev_str, l, rev_ls} = Enum.reduce(list, {[], 0, []}, fn
      %__MODULE__{s: s, l: l}, {acc_s, acc_l, acc_ls} ->
        {[s | acc_s], acc_l + tlen(l), [l | acc_ls]}
    end)
    %__MODULE__{s: Enum.reverse(rev_str), l: {l, Enum.reverse(rev_ls)}}
  end

  defp grapheme_to_binary(cp) when is_integer(cp), do: <<cp::utf8>>
  defp grapheme_to_binary(gc) when is_list(gc), do: for(cp <- gc, do: <<cp::utf8>>, into: "")

  defp len_of(binary) when is_binary(binary), do: codepoint_length(binary)

  defp len_of(list), do: len_of_list(list, 0)

  defp len_of_list([head | rest], so_far) do
    head = len_of(head)
    {count, list} = len_of_list(rest, so_far)
    {count + count_of(head), [head | list]}
  end

  defp len_of_list([], so_far), do: {0, []}

  defp len_of_list(head, so_far) do
    head
    |> len_of
    |> then(&{count_of(&1), &1})
  end

  defp count_of(integer) when is_integer(integer), do: integer
  defp count_of({integer, list}), do: integer

  def as_binary(iodata), do: IO.iodata_to_binary(iodata.s)

  def well_formed?(iodata), do: consistent?(iodata.s, iodata.l)

  defp consistent?(string, length) when is_binary(string) do
    codepoint_length(string) == length
  end

  defp consistent?([str_head | str_tail] = iodata, {size, [len_head | len_tail]}) do
    size_consistent? = codepoint_length(IO.iodata_to_binary(iodata)) == size

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

    a_str
    |> :diffy.diff(b_str)
    |> Enum.map(&from_diff_op/1)
  end


  # Convert diff ops to Otzel ops
  defp from_diff_op({:insert, text}) do
    %Insert{content: new(text)}
  end

  defp from_diff_op({:delete, text}) do
    %Otzel.Op.Delete{count: codepoint_length(text)}
  end

  defp from_diff_op({:equal, text}) do
    %Otzel.Op.Retain{target: codepoint_length(text)}
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
end

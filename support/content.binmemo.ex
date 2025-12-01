defmodule Otzel.Content.Binmemo do
  use Otzel.Content

  @enforce_keys ~w[s len]a
  defstruct @enforce_keys

  defp codepoint_split_at(string, count) do
    codepoints = String.codepoints(string)
    {Enum.take(codepoints, count) |> IO.iodata_to_binary(),
     Enum.drop(codepoints, count) |> IO.iodata_to_binary()}
  end

  def new(s) do
    %__MODULE__{s: s, len: Otzel._codepoints(s)}
  end

  def compose(left, right = %__MODULE__{}) do
    %__MODULE__{s: left.s <> right.s, len: left.len + right.len}
  end

  def merge_into(left, right) do
    %__MODULE__{s: right.s <> left.s, len: left.len + right.len}
  end

  def size(%{len: len}), do: len

  def take(string, count) when count < string.len do
    {head, tail} = codepoint_split_at(string.s, count)
    {%__MODULE__{s: head, len: count}, %__MODULE__{s: tail, len: string.len - count}}
  end

  def take(string, _count), do: {string, nil}

  def transform(_, _, _), do: raise("unimplemented")

  def invert(_, _), do: raise("unimplemented")

  def as_binary(s), do: s.s

  def diff(a, b) do
    a_str = as_binary(a)
    b_str = as_binary(b)

    a_str
    |> :diffy.diff(b_str)
    |> Enum.map(&from_diff_op/1)
  end

  defp from_diff_op({:insert, text}) do
    %Otzel.Op.Insert{content: new(text)}
  end

  defp from_diff_op({:delete, text}) do
    %Otzel.Op.Delete{count: Otzel._codepoints(text)}
  end

  defp from_diff_op({:equal, text}) do
    %Otzel.Op.Retain{target: Otzel._codepoints(text)}
  end

  def concatenate(list) do
    {strs, total_len} = Enum.reduce(list, {[], 0}, fn
      %__MODULE__{s: s, len: len}, {acc_s, acc_len} ->
        {[s | acc_s], acc_len + len}
    end)
    %__MODULE__{s: strs |> Enum.reverse() |> IO.iodata_to_binary(), len: total_len}
  end

  defimpl JSON.Encoder do
    def encode(binmemo, opts) do
      JSON.Encoder.encode(binmemo.s, opts)
    end
  end
end

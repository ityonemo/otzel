defimpl Otzel.Content, for: BitString do
  alias Otzel.Op.Insert
  alias Otzel.Op.Delete
  alias Otzel.Op.Retain

  # Use codepoints instead of graphemes for consistent counting
  defp codepoint_length(string), do: length(String.codepoints(string))

  defp codepoint_split_at(string, count) do
    codepoints = String.codepoints(string)
    {Enum.take(codepoints, count) |> IO.iodata_to_binary(),
     Enum.drop(codepoints, count) |> IO.iodata_to_binary()}
  end

  def size(string), do: codepoint_length(string)

  def take(string, count) do
    case codepoint_split_at(string, count) do
      {head, ""} -> {head, nil}
      split -> split
    end
  end

  def as_binary(string), do: string

  def compose(_, _), do: raise("unimplemented")

  def merge_into(left, right), do: right <> left

  def transform(_, _, _), do: raise("unimplemented")

  def invert(_, _), do: raise("unimplemented")

  def diff(a, b) do
    a
    |> :diffy.diff(b)
    |> Enum.map(&from_diff_op/1)
  end

  defp from_diff_op({:insert, text}), do: %Insert{content: text}
  defp from_diff_op({:delete, text}), do: %Delete{count: codepoint_length(text)}
  defp from_diff_op({:equal, text}), do: %Retain{target: codepoint_length(text)}

  def concatenate(contents), do: IO.iodata_to_binary(contents)
end

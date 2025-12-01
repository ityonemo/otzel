defimpl Otzel.Content, for: BitString do
  def new(string), do: string

  def size(string), do: Otzel._codepoints(string)

  def take(string, count) do
    case codepoint_split_at(string, count) do
      {head, ""} -> {head, nil}
      split -> split
    end
  end

  defp codepoint_split_at(string, count) do
    codepoints = String.codepoints(string)
    {Enum.take(codepoints, count) |> IO.iodata_to_binary(),
     Enum.drop(codepoints, count) |> IO.iodata_to_binary()}
  end

  def as_binary(string), do: string

  def compose(_, _), do: raise("unimplemented")

  def merge_into(left, right), do: right <> left

  def transform(_, _, _), do: raise("unimplemented")

  def invert(_, _), do: raise("unimplemented")

  def diff(a, b) do
    Otzel.Diff.diff(a, b, __MODULE__)
  end

  def concatenate(contents), do: IO.iodata_to_binary(contents)
end

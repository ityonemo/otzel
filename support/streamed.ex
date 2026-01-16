defmodule Otzel.Streamed do
  alias Otzel.Content.Iomemo
  alias Otzel.Op.Delete
  alias Otzel.Op.Retain

  defp utf8?(opts), do: Keyword.get(opts, :utf8, true)

  defp binstream(opts) do
    utf_generator =
      List.wrap(
        if utf8?(opts), do: {1, StreamData.string(:printable, min_length: 1, max_length: 10)}
      )

    StreamData.frequency(
      [{20, StreamData.string(:ascii, min_length: 1, max_length: 100)}] ++ utf_generator
    )
  end

  defp bintree(opts) do
    StreamData.tree(binstream(opts), fn binaries ->
      StreamData.map({binaries, binaries}, fn {left, right} ->
        [left | right]
      end)
    end)
  end

  defp graphemes_atomic?(data) do
    sum_len(data.s) == data.s |> IO.iodata_to_binary() |> String.length()
  end

  defp sum_len(data, acc \\ 0)
  defp sum_len([], acc), do: acc

  defp sum_len([head | tail], acc) do
    sum_len(tail, sum_len(head, acc))
  end

  defp sum_len(data, acc), do: String.length(data) + acc

  def iomemo(opts \\ []) do
    payload =
      if Keyword.get(opts, :simple, false) do
        datatype = if utf8?(opts), do: :ascii, else: :printable

        StreamData.string(datatype, min_length: 1, max_length: 100)
      else
        StreamData.one_of([binstream(opts), bintree(opts)])
      end

    payload
    |> StreamData.map(&Iomemo.new/1)
    |> StreamData.filter(&graphemes_atomic?/1)
  end

  defp attrs() do
    StreamData.one_of([
      nil,
      StreamData.map_of(
        StreamData.string(:alphanumeric, max_length: 25),
        StreamData.string(:alphanumeric, max_length: 25),
        length: 1
      )
    ])
  end

  defp nullable_attrs() do
    StreamData.one_of([
      nil,
      StreamData.map_of(
        StreamData.string(:alphanumeric, max_length: 25),
        StreamData.one_of([StreamData.string(:alphanumeric, max_length: 25), nil]),
        length: 1
      )
    ])
  end

  defp delete() do
    %{count: StreamData.integer(1..1000)}
    |> StreamData.fixed_map()
    |> StreamData.map(&struct!(Delete, &1))
  end

  defp insert(opts) do
    generator = Keyword.get(opts, :generator, iomemo(opts))

    {generator, attrs()}
    |> StreamData.tuple()
    |> StreamData.map(fn {str, attrs} ->
      Otzel.insert(str, attrs)
    end)
  end

  defp retain() do
    %{target: StreamData.integer(1..1000), attrs: nullable_attrs()}
    |> StreamData.fixed_map()
    |> StreamData.map(&struct!(Retain, &1))
  end

  def op(opts \\ []) do
    StreamData.one_of([insert(opts), retain(), delete()])
  end

  def ot(opts \\ []) do
    StreamData.list_of(op(opts), min_length: 1)
  end

  def insert_ot(opts \\ []) do
    StreamData.list_of(insert(opts), min_length: 1)
  end
end

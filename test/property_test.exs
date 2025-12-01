defmodule OtzelTest.PropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Otzel.Op.Delete
  alias Otzel.Op.Retain
  alias Otzel.Streamed

  import Kernel, except: [=~: 2]
  import OtzelTest.Op, only: [=~: 2]

  property "invert inverts" do
    check all(
            base <- Streamed.insert_ot(),
            change <- Streamed.ot(),
            max_run_time: 1_000
          ) do
      base_size = Otzel.size(base)
      change = take_counted(change, base_size)
      inverted = Otzel.invert(change, base)

      assert Otzel.compact(base) =~
               base
               |> Otzel.compose(change)
               |> Otzel.compose(inverted)
               |> Otzel.compact()
               |> remove_finals()
    end
  end

  property "diff makes a diff" do
    check all(
            text_a <- Streamed.insert_ot(),
            text_b <- Streamed.insert_ot(),
            max_run_time: 1_000
          ) do
      diff = Otzel.diff(text_a, text_b)

      assert Otzel.compact(text_b) =~
               text_a
               |> Otzel.compose(diff)
               |> Otzel.compact()
    end
  end

  defp with_split(transform_stream) do
    StreamData.bind(transform_stream, fn transform ->
      size = Otzel.size(transform)
      StreamData.tuple({StreamData.constant(transform), StreamData.integer(1..size)})
    end)
  end

  property "split is take/seek and concat is its inverse" do
    check all(
            {transform, split} <- with_split(Streamed.ot()),
            max_run_time: 1_000
          ) do
      transform = Otzel.compact(transform)
      {take, rest} = Otzel.split(transform, split)
      assert Otzel.seek(transform, split) == rest
      assert Otzel.take(transform, split) == take
      assert transform =~ Otzel.concat(take, rest)
    end
  end

  @json if function_exported?(:json, :encode, 1), do: JSON, else: Jason

  property "json roundtrip" do
    check all(
            transform <- Streamed.ot(),
            max_run_time: 1_000
          ) do
      transform = Otzel.compact(transform)
      assert transform =~ transform |> @json.encode!() |> @json.decode!() |> Otzel.from_json()
    end
  end

  defp remove_finals(ops) do
    case Enum.reverse(ops) do
      [%Retain{target: number} | rest] when is_number(number) ->
        Enum.reverse(rest)

      [%Delete{} | rest] ->
        Enum.reverse(rest)

      _ ->
        ops
    end
  end

  defp take_counted(ops, count), do: take_counted(ops, count, [])

  defp take_counted([%Retain{target: count} = retain | rest], base_size, so_far)
       when is_integer(count) do
    if count <= base_size do
      take_counted(rest, base_size - count, [%{retain | target: count} | so_far])
    else
      {take, _} = Retain.take(retain, base_size)
      Enum.reverse(so_far, [take])
    end
  end

  defp take_counted([%Delete{count: count} = delete | rest], base_size, so_far)
       when is_integer(count) do
    if count <= base_size do
      take_counted(rest, base_size - count, [%Delete{count: count} | so_far])
    else
      {take, _} = Delete.take(delete, base_size)
      Enum.reverse(so_far, [take])
    end
  end

  defp take_counted([thing | rest], base_size, so_far) do
    take_counted(rest, base_size, [thing | so_far])
  end

  defp take_counted([], _, so_far), do: Enum.reverse(so_far)
end

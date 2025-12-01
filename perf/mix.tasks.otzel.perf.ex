defmodule Mix.Tasks.Otzel.Perf do
  use Mix.Task

  @shortdoc "Run performance tests"

  alias Otzel.Content
  alias Otzel.Content.Binmemo
  alias Otzel.Streamed

  def to_delta(op), do: op |> JSON.encode!() |> JSON.decode!()

  @runs ~w[diff compose invert]a

  def run(args) do
    runs =
      case args do
        [] -> @runs
        other -> Enum.map(other, &String.to_atom/1)
      end

    Enum.each(runs, &do_run/1)
  end

  defp remap_inserts(pairs, module) do
    Enum.map(pairs, fn {a, b} ->
      {Content.remap_inserts(a, module), Content.remap_inserts(b, module)}
    end)
  end

  defp do_run(name) when name in @runs do
    iomemo_data = apply(__MODULE__, name, [])

    delta_data = Enum.map(iomemo_data, fn {a, b} -> {to_delta(a), to_delta(b)} end)
    binary_data = remap_inserts(iomemo_data, String)
    binmemo_data = remap_inserts(iomemo_data, Binmemo)

    Benchee.run(
      %{
        "#{name}:delta" => fn -> Enum.each(delta_data, &go(&1, Delta, name)) end,
        "#{name}:otzel:binary" => fn -> Enum.each(binary_data, &go(&1, Otzel, name)) end,
        "#{name}:otzel:binmemo" => fn -> Enum.each(binmemo_data, &go(&1, Otzel, name)) end,
        "#{name}:otzel:iomemo" => fn -> Enum.each(iomemo_data, &go(&1, Otzel, name)) end
      },
      time: 10,
      memory_time: 2
    )
  end

  def go(pair, module, model), do: apply(module, model, Tuple.to_list(pair))

  def diff do
    {Streamed.insert_ot(utf8: false), Streamed.insert_ot(utf8: false)}
    |> StreamData.tuple()
    |> Enum.take(20)
  end

  def compose do
    {Streamed.ot(utf8: false), Streamed.ot(utf8: false)}
    |> StreamData.tuple()
    |> Enum.take(1000)
  end

  def invert do
    {Streamed.ot(utf8: false), Streamed.ot(utf8: false)}
    |> StreamData.tuple()
    |> Enum.take(1000)
  end
end

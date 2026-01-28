defmodule Mix.Tasks.Otzel.Perf do
  use Mix.Task

  @shortdoc "Run performance tests"

  alias Otzel.Content
  alias Otzel.Content.Binmemo
  alias Otzel.Streamed

  def to_delta(op), do: op |> JSON.encode!() |> JSON.decode!()

  @runs ~w[diff compose invert diff_simple compose_simple invert_simple diff_typing compose_typing invert_typing]a

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

    # Extract base operation (diff, compose, invert) from name like diff_simple
    base_op = name |> Atom.to_string() |> String.split("_") |> hd() |> String.to_atom()

    delta_data = Enum.map(iomemo_data, fn {a, b} -> {to_delta(a), to_delta(b)} end)
    binary_data = remap_inserts(iomemo_data, String)
    binmemo_data = remap_inserts(iomemo_data, Binmemo)

    Benchee.run(
      %{
        "#{name}:delta" => fn -> Enum.each(delta_data, &go(&1, Delta, base_op)) end,
        "#{name}:otzel:binary" => fn -> Enum.each(binary_data, &go(&1, Otzel, base_op)) end,
        "#{name}:otzel:binmemo" => fn -> Enum.each(binmemo_data, &go(&1, Otzel, base_op)) end,
        "#{name}:otzel:iomemo" => fn -> Enum.each(iomemo_data, &go(&1, Otzel, base_op)) end
      },
      time: 10,
      memory_time: 2
    )
  end

  def go(pair, module, op), do: apply(module, op, Tuple.to_list(pair))

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

  # Simple benchmarks: single large text block (~10KB)
  @large_text String.duplicate("Lorem ipsum dolor sit amet, consectetur adipiscing elit. ", 200)
  @large_text_modified String.duplicate("Lorem ipsum dolor sit amet, consectetur adipiscing elit. ", 180) <> "MODIFIED ENDING."

  def diff_simple do
    doc1 = [Otzel.insert(@large_text)]
    doc2 = [Otzel.insert(@large_text_modified)]
    [{doc1, doc2}]
  end

  def compose_simple do
    doc = [Otzel.insert(@large_text)]
    # Simple change: insert at beginning, delete at end
    change = [Otzel.insert("PREFIX: "), Otzel.retain(String.length(@large_text) - 100), Otzel.delete(100)]
    [{doc, change}]
  end

  def invert_simple do
    doc = [Otzel.insert(@large_text)]
    change = [Otzel.insert("PREFIX: "), Otzel.retain(String.length(@large_text) - 100), Otzel.delete(100)]
    [{change, doc}]
  end

  # Typing simulation: many small sequential edits
  def diff_typing do
    # Simulate user typing a paragraph character by character
    base = "The quick brown fox jumps over the lazy dog. "
    edits = for i <- 1..50 do
      prefix = String.duplicate(base, i)
      {[Otzel.insert(prefix)], [Otzel.insert(prefix <> String.at(base, rem(i, String.length(base))))]}
    end
    edits
  end

  def compose_typing do
    # Simulate composing many small typing operations
    base_doc = [Otzel.insert("Hello")]
    chars = String.graphemes(" World, this is a test of typing simulation for benchmarking purposes.")

    edits = for {char, i} <- Enum.with_index(chars) do
      {[Otzel.retain(5 + i), Otzel.insert(char)], [Otzel.retain(6 + i)]}
    end

    # Return pairs of (current_doc, small_change)
    {pairs, _} = Enum.reduce(edits, {[], base_doc}, fn {change, _}, {acc, doc} ->
      new_doc = Otzel.compose(doc, change)
      {[{doc, change} | acc], new_doc}
    end)

    Enum.reverse(pairs)
  end

  def invert_typing do
    # Same as compose_typing but for invert
    base_doc = [Otzel.insert("Hello")]
    chars = String.graphemes(" World, this is a test of typing simulation for benchmarking purposes.")

    edits = for {char, i} <- Enum.with_index(chars) do
      [Otzel.retain(5 + i), Otzel.insert(char)]
    end

    {pairs, _} = Enum.reduce(edits, {[], base_doc}, fn change, {acc, doc} ->
      new_doc = Otzel.compose(doc, change)
      {[{change, doc} | acc], new_doc}
    end)

    Enum.reverse(pairs)
  end
end

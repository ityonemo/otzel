defmodule OtzelTest.Content.IomemoTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import StreamData, only: []

  alias Otzel.Content.Iomemo
  alias Otzel.Streamed

  # Helper to split by codepoints instead of graphemes
  defp codepoint_split_at(string, count) do
    codepoints = String.codepoints(string)
    {Enum.take(codepoints, count) |> IO.iodata_to_binary(),
     Enum.drop(codepoints, count) |> IO.iodata_to_binary()}
  end

  @tag :property
  property "new" do
    check all(
            data <- Streamed.iomemo(),
            max_runs: 10_000
          ) do
      assert Iomemo.well_formed?(data)
    end
  end

  @tag :property
  property "take" do
    check all(
            data <- Streamed.iomemo(),
            count <- StreamData.integer(1..100),
            max_runs: 10_000
          ) do
      {new, rest} = Iomemo.take(data, count)
      assert Iomemo.well_formed?(new)
      if rest, do: Iomemo.well_formed?(rest)

      {prefix, _} = data.s |> IO.iodata_to_binary() |> codepoint_split_at(count)
      assert prefix == IO.iodata_to_binary(new.s)
    end
  end

  describe "take with a base string" do
    @base_string Iomemo.new("ABC")
    test "internally" do
      assert {%{s: "A"}, %{s: "BC"}} = Iomemo.take(@base_string, 1)
    end

    test "at or past the end" do
      assert {@base_string, nil} = Iomemo.take(@base_string, 3)
      assert {@base_string, nil} = Iomemo.take(@base_string, 4)
    end
  end

  describe "take with a proper list" do
    @base_list Iomemo.new(["AB", "CD"])
    test "before the boundary" do
      assert {%{s: "A"}, %{s: ["B", "CD"]}} = Iomemo.take(@base_list, 1)
    end

    test "at the boundary" do
      assert {%{s: "AB"}, %{s: ["CD"]}} = Iomemo.take(@base_list, 2)
    end

    test "after the boundary" do
      assert {%{s: ["AB" | "C"]}, %{s: ["D"]}} = Iomemo.take(@base_list, 3)
    end

    test "at the end" do
      assert {@base_list, nil} = Iomemo.take(@base_list, 4)
      assert {@base_list, nil} = Iomemo.take(@base_list, 5)
    end
  end

  describe "take with an improper list" do
    @ilist Iomemo.new(["AB" | "CD"])
    test "before the boundary" do
      assert {%{s: "A"}, %{s: ["B" | "CD"]}} = Iomemo.take(@ilist, 1)
    end

    test "at the boundary" do
      assert {%{s: "AB"}, %{s: "CD"}} = Iomemo.take(@ilist, 2)
    end

    test "after the boundary" do
      assert {%{s: ["AB" | "C"]}, %{s: "D"}} = Iomemo.take(@ilist, 3)
    end

    test "at/after the end" do
      assert {@ilist, nil} = Iomemo.take(@ilist, 4)
      assert {@ilist, nil} = Iomemo.take(@ilist, 5)
    end
  end

  describe "take with a nested improper list" do
    @nilist Iomemo.new([["AB" | "C"], "D"])
    test "in the nested list" do
      assert {%{s: "A"}, %{s: [["B" | "C"], "D"]}} = Iomemo.take(@nilist, 1)
    end

    test "at the boundary in the nested list" do
      assert {%{s: "AB"}, %{s: ["C", "D"]}} = Iomemo.take(@nilist, 2)
    end

    test "after the the nested list" do
      assert {%{s: ["AB" | "C"]}, %{s: ["D"]}} = Iomemo.take(@nilist, 3)
    end

    test "at/after the end" do
      assert {@nilist, nil} = Iomemo.take(@nilist, 4)
      assert {@nilist, nil} = Iomemo.take(@nilist, 5)
    end

    test "doubly nested" do
      double = Iomemo.new([[["A" | "B"] | "C"] | "D"])
      assert {%{s: [["A" | "B"] | "C"]}, %{s: "D"}} = Iomemo.take(double, 3)
    end
  end

  test "take regression" do
    a = Iomemo.new(["AB" | "C"])
    {a, b} = Iomemo.take(a, 1)
    assert Iomemo.well_formed?(a)
    assert Iomemo.well_formed?(b)
  end
end

defmodule Otzel.RegressionTest do
  @moduledoc """
  Regression tests for Otzel bugs found during Labrador development.
  These should be moved to the Otzel repo once fixed.
  """

  use ExUnit.Case, async: true

  @moduletag :lib

  # Helper to extract string content from ops for semantic comparison
  defp to_string_content(ops) do
    ops
    |> Enum.map(fn %Otzel.Op.Insert{content: content} -> to_string(content) end)
    |> Enum.join()
  end

  describe "invert" do
    test "invert inverts - property test regression" do
      # Full values from property test failure with seed 496357
      base = [
        %Otzel.Op.Insert{
          content: %Otzel.Content.Iomemo{s: ">,p<\"jlaV:aHD[6\\`bGsMu>=pT", l: 26},
          attrs: nil
        },
        %Otzel.Op.Insert{
          content: %Otzel.Content.Iomemo{
            s: [
              [
                [
                  "m{^$7z+&v$0t=~8\"2!!.Q}=_+Npo(n82_<vp-bCQ3CVC",
                  "~{QxxPQVWCk*gUR'KYVE-X*wk" | "􊪽𣯿"
                ]
                | "{)Vj`\"!!3T"
              ],
              ["6yS+(n07j" | "a@zT=4Xy~+\"u;`~w<~U3am34VTLiA&czMOK!"],
              ["]_c1pmLmIlV_fCZg= " | "򘞛񲁲򻔳򭫾򰨏󪄟"],
              "p$Ok@:tdAQ" | "8gXhARG:!<z7^N<bttn"
            ],
            l: {179, [{81, [{71, [44, 25 | 2]} | 10]}, {45, [9 | 36]}, {24, [18 | 6]}, 10 | 19]}
          },
          attrs: %{"X2VXZgGUviSHKWLWg" => "RZnISZvlYGtUZhPZljCW"}
        },
        %Otzel.Op.Insert{
          content: %Otzel.Content.Iomemo{s: "< #E4H*\\", l: 8},
          attrs: %{"aVSL8X7H" => "95FmQu"}
        },
        %Otzel.Op.Insert{
          content: %Otzel.Content.Iomemo{s: ["󨠈𔳡󑍚𷼯򠃃񨪮𢁑񦰰" | ">puO_'"], l: {14, [8 | 6]}},
          attrs: %{"MP" => "mHQspwX1YyM5fa"}
        }
      ]

      change = [
        %Otzel.Op.Delete{count: 5},
        %Otzel.Op.Retain{target: 810, attrs: %{"VzDZB9vToz76LFe8" => nil}},
        %Otzel.Op.Delete{count: 112}
      ]

      base_size = Otzel.size(base)
      change = take_counted(change, base_size)
      inverted = Otzel.invert(change, base)

      result =
        base
        |> Otzel.compose(change)
        |> Otzel.compose(inverted)
        |> Otzel.compact()

      assert to_string_content(Otzel.compact(base)) == to_string_content(result)
    end
  end

  # From property_test.exs
  defp take_counted(ops, count), do: take_counted(ops, count, [])

  defp take_counted([%Otzel.Op.Retain{target: count} = retain | rest], base_size, so_far)
       when is_integer(count) do
    if count <= base_size do
      take_counted(rest, base_size - count, [%{retain | target: count} | so_far])
    else
      {take, _} = Otzel.Op.Retain.take(retain, base_size)
      Enum.reverse(so_far, [take])
    end
  end

  defp take_counted([%Otzel.Op.Delete{count: count} = delete | rest], base_size, so_far)
       when is_integer(count) do
    if count <= base_size do
      take_counted(rest, base_size - count, [%Otzel.Op.Delete{count: count} | so_far])
    else
      {take, _} = Otzel.Op.Delete.take(delete, base_size)
      Enum.reverse(so_far, [take])
    end
  end

  defp take_counted([thing | rest], base_size, so_far) do
    take_counted(rest, base_size, [thing | so_far])
  end

  defp take_counted([], _, so_far), do: Enum.reverse(so_far)

  describe "diff/2 with trailing newlines" do
    test "correctly diffs when inserting text before trailing newline" do
      old = [Otzel.insert("Hello\n")]
      new = [Otzel.insert("Hello World\n")]

      diff = Otzel.diff(old, new)
      result = Otzel.compose(old, diff)

      assert to_string_content(result) == to_string_content(new)
    end

    test "correctly diffs when appending to text with trailing newline" do
      old = [Otzel.insert("A\n")]
      new = [Otzel.insert("AB\n")]

      diff = Otzel.diff(old, new)
      result = Otzel.compose(old, diff)

      assert to_string_content(result) == to_string_content(new)
    end

    test "correctly diffs multi-line content" do
      old = [Otzel.insert("Line1\nLine2\n")]
      new = [Otzel.insert("Line1\nLine2 modified\n")]

      diff = Otzel.diff(old, new)
      result = Otzel.compose(old, diff)

      assert to_string_content(result) == to_string_content(new)
    end

    test "correctly diffs when removing text before trailing newline" do
      old = [Otzel.insert("Hello World\n")]
      new = [Otzel.insert("Hello\n")]

      diff = Otzel.diff(old, new)
      result = Otzel.compose(old, diff)

      assert to_string_content(result) == to_string_content(new)
    end
  end
end

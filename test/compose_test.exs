defmodule OtzelTest.ComposeTest do
  use ExUnit.Case, async: true

  alias OtzelTest.Op
  alias OtzelTest.Content.Integer
  alias OtzelTest.Content.Image
  import Kernel, except: [=~: 2]
  import OtzelTest.Op, only: [=~: 2]

  describe ".compose/2 (basic)" do
    test "insert + insert" do
      a = [Otzel.insert("A")]
      b = [Otzel.insert("B")]
      expected = [Otzel.insert("BA")]

      assert Otzel.compose(a, b) =~ expected
    end

    test "insert + insert (with attributes)" do
      a = [Otzel.insert("A", %{"bold" => true})]
      b = [Otzel.insert("B", %{"bold" => true})]
      expected = [Otzel.insert("BA", %{"bold" => true})]

      assert Otzel.compose(a, b) =~ expected
    end

    test "insert + retain" do
      a = [Otzel.insert("A")]
      b = [Otzel.retain(1, %{"bold" => true, "color" => "red", "font" => nil})]
      expected = [Otzel.insert("A", %{"bold" => true, "color" => "red"})]

      assert Otzel.compose(a, b) == expected
    end

    test "insert + delete" do
      a = [Otzel.insert("A")]
      b = [Otzel.delete(1)]
      expected = []

      assert Otzel.compose(a, b) == expected
    end

    test "delete + insert" do
      a = [Otzel.delete(1)]
      b = [Otzel.insert("B")]
      expected = [Otzel.insert("B"), Otzel.delete(1)]

      assert Otzel.compose(a, b) == expected
    end

    test "delete + retain" do
      a = [Otzel.delete(1)]
      b = [Otzel.retain(1, %{"bold" => true, "color" => "red"})]
      expected = [Otzel.delete(1), Otzel.retain(1, %{"bold" => true, "color" => "red"})]

      assert Otzel.compose(a, b) == expected
    end

    test "delete + delete" do
      a = [Otzel.delete(1)]
      b = [Otzel.delete(1)]
      expected = [Otzel.delete(2)]

      assert Otzel.compose(a, b) == expected
    end

    test "retain + insert" do
      a = [Otzel.retain(1, %{"color" => "blue"})]
      b = [Otzel.insert("B")]
      expected = [Otzel.insert("B"), Otzel.retain(1, %{"color" => "blue"})]

      assert Otzel.compose(a, b) == expected
    end

    test "retain + retain (plain)" do
      a = b = [Otzel.retain(1)]
      assert Otzel.compose(a, b) == []
    end

    test "retain + retain (with attributes)" do
      a = [Otzel.retain(1, %{"color" => "blue"})]
      b = [Otzel.retain(1, %{"bold" => true, "color" => "red", "font" => nil})]
      expected = [Otzel.retain(1, %{"bold" => true, "color" => "red", "font" => nil})]

      assert Otzel.compose(a, b) == expected
    end

    test "retain + delete" do
      a = [Otzel.retain(1, %{"color" => "blue"})]
      b = [Otzel.delete(1)]
      expected = [Otzel.delete(1)]

      assert Otzel.compose(a, b) == expected
    end

    test "insert in middle of text" do
      a = [Otzel.insert("Hello")]
      b = [Otzel.retain(3), Otzel.insert("X")]
      expected = [Otzel.insert("HelXlo")]

      assert Otzel.compose(a, b) =~ expected
    end

    test "insert/delete ordering" do
      base = [Otzel.insert("Hello")]
      insert_first = [Otzel.retain(3), Otzel.insert("X"), Otzel.delete(1)]
      delete_first = [Otzel.retain(3), Otzel.delete(1), Otzel.insert("X")]
      expected = [Otzel.insert("HelXo")]

      assert Otzel.compose(base, insert_first) =~ expected
      assert Otzel.compose(base, delete_first) =~ expected
    end

    test "insert embed" do
      embed = Image.new("image.png")
      a = [Otzel.insert(embed, %{"width" => "300"})]
      b = [Otzel.retain(1, %{"height" => "200"})]
      expected = [Otzel.insert(embed, %{"width" => "300", "height" => "200"})]

      assert Otzel.compose(a, b) == expected
    end

    test "delete entire text" do
      a = [Otzel.retain(4), Otzel.insert("Hello")]
      b = [Otzel.delete(9)]
      expected = [Otzel.delete(4)]

      assert Otzel.compose(a, b) == expected
    end

    test "retain more than length of text" do
      a = [Otzel.insert("Hello")]
      b = [Otzel.retain(10)]
      expected = [Otzel.insert("Hello")]

      assert Otzel.compose(a, b) == expected
    end

    test "retain empty embed" do
      a = [Otzel.insert(Op.embed([]))]
      b = [Otzel.retain(1)]

      assert Otzel.compose(a, b) == a
    end

    test "remove all attributes" do
      a = [Otzel.insert("A", %{"bold" => true})]
      b = [Otzel.retain(1, %{"bold" => nil})]
      expected = [Otzel.insert("A")]

      assert Otzel.compose(a, b) == expected
    end

    test "remove all embed attributes" do
      a = [Otzel.insert(Integer.new(2), %{"bold" => true})]
      b = [Otzel.retain(1, %{"bold" => nil})]
      expected = [Otzel.insert(Integer.new(2))]

      assert Otzel.compose(a, b) == expected
    end

    test "retain start optimization" do
      a = [
        Otzel.insert("A", %{"bold" => true}),
        Otzel.insert("B"),
        Otzel.insert("C", %{"bold" => true}),
        Otzel.delete(1)
      ]

      b = [
        Otzel.retain(3),
        Otzel.insert("D")
      ]

      expected = [
        Otzel.insert("A", %{"bold" => true}),
        Otzel.insert("B"),
        Otzel.insert("C", %{"bold" => true}),
        Otzel.insert("D"),
        Otzel.delete(1)
      ]

      assert Otzel.compose(a, b) == expected
    end

    test "retain start optimization split" do
      a = [
        Otzel.insert("A", %{"bold" => true}),
        Otzel.insert("B"),
        Otzel.insert("C", %{"bold" => true}),
        Otzel.retain(5),
        Otzel.delete(1)
      ]

      b = [
        Otzel.retain(4),
        Otzel.insert("D")
      ]

      expected = [
        Otzel.insert("A", %{"bold" => true}),
        Otzel.insert("B"),
        Otzel.insert("C", %{"bold" => true}),
        Otzel.retain(1),
        Otzel.insert("D"),
        Otzel.retain(4),
        Otzel.delete(1)
      ]

      assert Otzel.compose(a, b) == expected
    end

    test "retain end optimization" do
      a = [
        Otzel.insert("A", %{"bold" => true}),
        Otzel.insert("B"),
        Otzel.insert("C", %{"bold" => true})
      ]

      b = [Otzel.delete(1)]
      expected = [Otzel.insert("B"), Otzel.insert("C", %{"bold" => true})]

      assert Otzel.compose(a, b) == expected
    end

    test "retain end optimization join" do
      a = [
        Otzel.insert("A", %{"bold" => true}),
        Otzel.insert("B"),
        Otzel.insert("C", %{"bold" => true}),
        Otzel.insert("D"),
        Otzel.insert("E", %{"bold" => true}),
        Otzel.insert("F")
      ]

      b = [
        Otzel.retain(1),
        Otzel.delete(1)
      ]

      expected = [
        Otzel.insert("AC", %{"bold" => true}),
        Otzel.insert("D"),
        Otzel.insert("E", %{"bold" => true}),
        Otzel.insert("F")
      ]

      assert Otzel.compose(a, b) =~ expected
    end

    test "retain at boundary" do
      a = [Otzel.insert("ab"), Otzel.insert("cd")]
      b = [Otzel.retain(2), Otzel.delete(1)]
      expected = [Otzel.insert("abd")]

      assert Otzel.compose(a, b) =~ expected
    end

    test "non-compact" do
      a = [
        Otzel.insert("2", %{"link" => "link"}),
        Otzel.insert("\n")
      ]

      b = [Otzel.retain(1), Otzel.delete(1)]
      expected = [Otzel.insert("2", %{"link" => "link"})]

      assert Otzel.compose(a, b) =~ expected
    end

    test "overlapping delete and retain" do
      a = [
        Otzel.retain(1),
        Otzel.retain(2, %{"bold" => true, "author" => "user1"})
      ]

      b = [
        Otzel.retain(2),
        Otzel.delete(2)
      ]

      assert Otzel.compose(a, b) == [
               Otzel.retain(1),
               Otzel.retain(1, %{"bold" => true, "author" => "user1"}),
               Otzel.delete(2)
             ]
    end
  end

  describe ".compose/2 (custom embeds)" do
    test "retain an embed with a number" do
      a = [Otzel.insert(Op.embed(Otzel.insert("a")))]
      b = [Otzel.retain(1, %{"bold" => true})]
      expected = [Otzel.insert(Op.embed(Otzel.insert("a")), %{"bold" => true})]

      assert Otzel.compose(a, b) == expected
    end

    test "retain a number with an embed" do
      a = [Otzel.retain(10, %{"bold" => true})]
      b = [Otzel.retain(Op.embed(Otzel.insert("b")))]

      expected = [
        Otzel.retain(Op.embed(Otzel.insert("b")), %{"bold" => true}),
        Otzel.retain(9, %{"bold" => true})
      ]

      assert Otzel.compose(a, b) == expected
    end

    test "retain an embed with an embed" do
      a = [Otzel.retain(Op.embed(Otzel.insert("a")))]
      b = [Otzel.retain(Op.embed(Otzel.insert("b")))]
      expected = [Otzel.retain(Op.embed(Otzel.insert("ba")))]

      assert Otzel.compose(a, b) =~ expected
    end

    test "delete a retain" do
      a = [Otzel.retain(Op.embed(Otzel.insert("a")))]
      b = [Otzel.delete(1)]
      expected = [Otzel.delete(1)]

      assert Otzel.compose(a, b) == expected
    end
  end

  use ExUnitProperties
  alias Otzel.Streamed
  alias Otzel.Content

  for type <- [String, Otzel.Content.Binmemo] do
    property "compose for #{type}" do
      check all(
              a <- Streamed.ot(),
              b <- Streamed.ot(),
              max_runs: 100
            ) do
        a_remapped = Content.remap_inserts(a, unquote(type))
        b_remapped = Content.remap_inserts(b, unquote(type))

        assert Otzel.compose(a_remapped, b_remapped) =~ Otzel.compose(a, b)
      end
    end
  end
end

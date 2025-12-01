defmodule OtzelTest.InvertTest do
  use ExUnit.Case, async: true
  alias OtzelTest.Op

  import Kernel, except: [=~: 2]
  import Op, only: [=~: 2]

  describe ".invert/2 (basic)" do
    test "insert" do
      change = [Otzel.retain(2), Otzel.insert("A")]
      base = [Otzel.insert("123456")]
      expected = [Otzel.retain(2), Otzel.delete(1)]
      inverted = Otzel.invert(change, base)

      assert inverted == expected
      assert base =~ base |> Otzel.compose(change) |> Otzel.compose(inverted)
    end

    test "delete" do
      change = [Otzel.retain(2), Otzel.delete(3)]
      base = [Otzel.insert("123456")]
      expected = [Otzel.retain(2), Otzel.insert("345")]
      inverted = Otzel.invert(change, base)

      assert inverted == expected
      assert base =~ base |> Otzel.compose(change) |> Otzel.compose(inverted)
    end

    test "retain" do
      change = [Otzel.retain(2), Otzel.retain(3, %{"bold" => true})]
      base = [Otzel.insert("123456")]
      expected = [Otzel.retain(2), Otzel.retain(3, %{"bold" => nil})]
      inverted = Otzel.invert(change, base)

      assert inverted == expected
      assert base =~ base |> Otzel.compose(change) |> Otzel.compose(inverted)
    end

    test "retain on a delta with different attributes" do
      base = [Otzel.insert("123"), Otzel.insert("4", %{"bold" => true})]
      change = [Otzel.retain(4, %{"italic" => true})]
      expected = [Otzel.retain(4, %{"italic" => nil})]
      inverted = Otzel.invert(change, base)

      assert inverted == expected
      assert base == base |> Otzel.compose(change) |> Otzel.compose(inverted)
    end

    test "combined" do
      change = [
        Otzel.retain(2),
        Otzel.delete(2),
        Otzel.insert("AB", %{"italic" => true}),
        Otzel.retain(2, %{"italic" => nil, "bold" => true}),
        Otzel.retain(2, %{"color" => "red"}),
        Otzel.delete(1)
      ]

      base = [
        Otzel.insert("123", %{"bold" => true}),
        Otzel.insert("456", %{"italic" => true}),
        Otzel.insert("789", %{"bold" => true, "color" => "red"})
      ]

      expected = [
        Otzel.retain(2),
        Otzel.insert("3", %{"bold" => true}),
        Otzel.insert("4", %{"italic" => true}),
        Otzel.delete(2),
        Otzel.retain(2, %{"italic" => true, "bold" => nil}),
        Otzel.retain(2),
        Otzel.insert("9", %{"bold" => true, "color" => "red"})
      ]

      inverted = Otzel.invert(change, base)
      assert inverted == expected

      assert base =~ base |> Otzel.compose(change) |> Otzel.compose(inverted)
    end

    test "regression1" do
      base = [Otzel.insert("I"), Otzel.insert("P")]
      change = [%Otzel.Op.Delete{count: 2}]

      inverted = Otzel.invert(change, base)

      assert [Otzel.insert("IP")] =~ inverted
    end

    test "regression2" do
      base = [
        %Otzel.Op.Insert{content: "I2", attrs: %{"a" => "b"}},
        %Otzel.Op.Insert{content: "Q", attrs: nil}
      ]

      change = [%Otzel.Op.Delete{count: 3}]

      inverted = Otzel.invert(change, base)

      assert [%{content: "I2"}, %{content: "Q"}] = inverted
    end
  end

  describe ".invert/2 (custom embeds)" do
    @describetag :skip
    @describetag custom_embeds: [TestEmbed]

    test "invert a normal change" do
      change = [Otzel.retain(1, %{"bold" => true})]
      base = [Otzel.insert(Op.embed(Otzel.insert("a")))]
      expected = [Otzel.retain(1, %{"bold" => nil})]
      inverted = Otzel.invert(change, base)

      assert inverted == expected
      assert base == base |> Otzel.compose(change) |> Otzel.compose(inverted)
    end

    test "invert an embed change" do
      change = [Otzel.retain(Op.embed(Otzel.insert("b")))]
      base = [Otzel.insert(Op.embed(Otzel.insert("a")))]
      expected = [Otzel.retain(Op.embed(Otzel.delete(1)))]
      inverted = Otzel.invert(change, base)

      assert inverted == expected
      assert base == base |> Otzel.compose(change) |> Otzel.compose(inverted)
    end

    test "invert an embed change with numbers" do
      delta = [
        Otzel.retain(1),
        Otzel.retain(1, %{"bold" => true}),
        Otzel.retain(Op.embed(Otzel.insert("b")))
      ]

      base = [Otzel.insert("\n\n"), Otzel.insert(Op.embed(Otzel.insert("a")))]

      expected = [
        Otzel.retain(1),
        Otzel.retain(1, %{"bold" => nil}),
        Otzel.retain(Op.embed(Otzel.delete(1)))
      ]

      inverted = Otzel.invert(delta, base)

      assert inverted == expected
      assert base =~ base |> Otzel.compose(delta) |> Otzel.compose(inverted)
    end

    test "respects base attributes" do
      delta = [
        Otzel.delete(1),
        Otzel.retain(1, %{"header" => 2}),
        Otzel.retain(Op.embed(Otzel.insert("b")), %{"padding" => 10, "margin" => 0})
      ]

      base = [
        Otzel.insert("\n"),
        Otzel.insert("\n", %{"header" => 1}),
        Otzel.insert(Op.embed(Otzel.insert("a")), %{"margin" => 10})
      ]

      expected = [
        Otzel.insert("\n"),
        Otzel.retain(1, %{"header" => 1}),
        Otzel.retain(Op.embed(Otzel.delete(1)), %{"padding" => nil, "margin" => 10})
      ]

      inverted = Otzel.invert(delta, base)

      assert inverted == expected
      assert base == base |> Otzel.compose(delta) |> Otzel.compose(inverted)
    end

    test "works with multiple embeds" do
      delta = [
        Otzel.retain(1),
        Otzel.retain(Op.embed(Otzel.delete(1))),
        Otzel.retain(Op.embed(Otzel.delete(1)))
      ]

      base = [
        Otzel.insert("\n"),
        Otzel.insert(Op.embed(Otzel.insert("a"))),
        Otzel.insert(Op.embed(Otzel.insert("b")))
      ]

      expected = [
        Otzel.retain(1),
        Otzel.retain(Op.embed(Otzel.insert("a"))),
        Otzel.retain(Op.embed(Otzel.insert("b")))
      ]

      inverted = Otzel.invert(delta, base)

      assert inverted == expected

      base |> Otzel.compose(delta)
      assert base =~ base |> Otzel.compose(delta) |> Otzel.compose(inverted)
    end
  end

  use ExUnitProperties
  alias Otzel.Streamed
  alias Otzel.Content

  for type <- [String, Otzel.Content.Binmemo] do
    property "invert for #{type}" do
      check all(
              a <- Streamed.ot(),
              b <- Streamed.ot(),
              max_run_time: 1000
            ) do
        a_remapped = Content.remap_inserts(a, unquote(type))
        b_remapped = Content.remap_inserts(b, unquote(type))

        assert Otzel.invert(a_remapped, b_remapped) =~ Otzel.invert(a, b)
      end
    end
  end
end

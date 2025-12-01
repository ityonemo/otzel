defmodule OtzelTest.TransformTest do
  use ExUnit.Case, async: true

  alias OtzelTest.Op

  describe ".transform/3 (basic)" do
    test "insert + insert" do
      a = [Otzel.insert("A")]
      b = [Otzel.insert("B")]

      assert Otzel.transform(a, b, :left) == [Otzel.retain(1), Otzel.insert("B")]
      assert Otzel.transform(a, b, :right) == [Otzel.insert("B")]
    end

    test "insert + retain" do
      a = [Otzel.insert("A")]
      b = [Otzel.retain(1, %{"bold" => true, "color" => "red"})]

      assert Otzel.transform(a, b) == [Otzel.retain(1) | b]
    end

    test "insert + delete" do
      a = [Otzel.insert("A")]
      b = [Otzel.delete(1)]

      assert Otzel.transform(a, b) == [Otzel.retain(1), Otzel.delete(1)]
    end

    test "delete + insert" do
      a = [Otzel.delete(1)]
      b = [Otzel.insert("B")]

      assert Otzel.transform(a, b, :left) == b
    end

    test "delete + retain" do
      a = [Otzel.delete(1)]
      b = [Otzel.retain(1, %{"bold" => true, "color" => "red"})]

      assert Otzel.transform(a, b, :left) == []
    end

    test "delete + delete" do
      a = b = [Otzel.delete(1)]

      assert Otzel.transform(a, b) == []
    end

    test "retain + insert" do
      a = [Otzel.retain(1, %{"color" => "blue"})]
      b = [Otzel.insert("B")]

      assert Otzel.transform(a, b, :left) == b
    end

    test "retain + retain (with priority)" do
      a = [Otzel.retain(1, %{"color" => "blue"})]
      b = [Otzel.retain(1, %{"color" => "red", "bold" => true})]

      assert Otzel.transform(a, b, :left) == [Otzel.retain(1, %{"bold" => true})]
      assert Otzel.transform(b, a, :left) == []
    end

    test "retain + retain (without priority)" do
      a = [Otzel.retain(1, %{"color" => "blue"})]
      b = [Otzel.retain(1, %{"color" => "red", "bold" => true})]

      assert Otzel.transform(a, b, :right) == [
               Otzel.retain(1, %{"bold" => true, "color" => "red"})
             ]

      assert Otzel.transform(b, a, :right) == [Otzel.retain(1, %{"color" => "blue"})]
    end

    test "retain + delete" do
      a = [Otzel.retain(1, %{"color" => "blue"})]
      b = [Otzel.delete(1)]

      assert Otzel.transform(a, b, :left) == b
    end

    test "alternating edits" do
      a = [Otzel.retain(2), Otzel.insert("si"), Otzel.delete(5)]

      b = [
        Otzel.retain(1),
        Otzel.insert("e"),
        Otzel.delete(5),
        Otzel.retain(1),
        Otzel.insert("ow")
      ]

      assert Otzel.transform(a, b, :right) == [
               Otzel.retain(1),
               Otzel.insert("e"),
               Otzel.delete(1),
               Otzel.retain(2),
               Otzel.insert("ow")
             ]

      assert Otzel.transform(b, a, :right) == [
               Otzel.retain(2),
               Otzel.insert("si"),
               Otzel.delete(1)
             ]
    end

    test "conflicting appends" do
      a = [Otzel.retain(3), Otzel.insert("aa")]
      b = [Otzel.retain(3), Otzel.insert("bb")]

      assert Otzel.transform(a, b, :left) == [Otzel.retain(5), Otzel.insert("bb")]
      assert Otzel.transform(b, a, :right) == [Otzel.retain(3), Otzel.insert("aa")]
    end

    test "prepend + append" do
      a = [Otzel.insert("aa")]
      b = [Otzel.retain(3), Otzel.insert("bb")]

      assert Otzel.transform(a, b, :right) == [Otzel.retain(5), Otzel.insert("bb")]
      assert Otzel.transform(b, a, :right) == [Otzel.insert("aa")]
    end

    test "trailing deletes with differing lengths" do
      a = [Otzel.retain(2), Otzel.delete(1)]
      b = [Otzel.delete(3)]

      assert Otzel.transform(a, b, :right) == [Otzel.delete(2)]
      assert Otzel.transform(b, a, :right) == []
    end
  end

  describe ".transform/3 (custom embeds)" do
    test "transform an embed change with number" do
      a = [Otzel.retain(1)]
      b = [Otzel.retain(Op.embed(Otzel.insert("b")))]

      expected = [Otzel.retain(Op.embed(Otzel.insert("b")))]

      assert Otzel.transform(a, b, :right) == expected
      assert Otzel.transform(a, b, :left) == expected
    end

    test "transform an embed change" do
      a = [Otzel.retain(Op.embed(Otzel.insert("a")))]
      b = [Otzel.retain(Op.embed(Otzel.insert("b")))]

      with_priority = [Otzel.retain(Op.embed([Otzel.retain(1), Otzel.insert("b")]))]
      without_priority = [Otzel.retain(Op.embed(Otzel.insert("b")))]

      assert Otzel.transform(a, b, :left) == with_priority
      assert Otzel.transform(a, b, :right) == without_priority
    end
  end
end

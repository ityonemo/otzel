defmodule OtzelTest.EctoTest do
  use ExUnit.Case, async: true

  alias Otzel.Ecto.Delta

  describe "type/0" do
    test "returns :map" do
      assert Delta.type() == :map
    end
  end

  describe "cast/1" do
    test "casts a list of Otzel operations" do
      delta = [Otzel.insert("Hello"), Otzel.retain(5)]
      assert {:ok, ^delta} = Delta.cast(delta)
    end

    test "casts an empty list" do
      assert {:ok, []} = Delta.cast([])
    end

    test "casts a JSON string" do
      json = ~s([{"insert": "Hello"}])
      assert {:ok, [%Otzel.Op.Insert{content: "Hello", attrs: nil}]} = Delta.cast(json)
    end

    test "returns error for invalid input" do
      assert :error = Delta.cast("not json")
      assert :error = Delta.cast(123)
      assert :error = Delta.cast(%{})
    end
  end

  describe "load/1" do
    test "loads JSON maps to Otzel operations" do
      data = [%{"insert" => "Hello"}, %{"insert" => " World", "attributes" => %{"bold" => true}}]

      assert {:ok, delta} = Delta.load(data)
      assert [%Otzel.Op.Insert{content: "Hello"}, %Otzel.Op.Insert{attrs: %{"bold" => true}}] = delta
    end

    test "loads an empty list" do
      assert {:ok, []} = Delta.load([])
    end

    test "returns error for non-list" do
      assert :error = Delta.load(%{})
      assert :error = Delta.load("string")
    end
  end

  describe "dump/1" do
    test "dumps Otzel operations to JSON-compatible maps" do
      delta = [Otzel.insert("Hello"), Otzel.insert(" World", %{"bold" => true})]

      assert {:ok, data} = Delta.dump(delta)
      assert [%{"insert" => "Hello"}, %{"insert" => " World", "attributes" => %{"bold" => true}}] = data
    end

    test "dumps an empty list" do
      assert {:ok, []} = Delta.dump([])
    end

    test "returns error for non-list" do
      assert :error = Delta.dump(%{})
      assert :error = Delta.dump("string")
    end
  end

  describe "round-trip" do
    test "dump then load preserves delta" do
      delta = [
        Otzel.insert("Hello "),
        Otzel.insert("World", %{"bold" => true}),
        Otzel.retain(5, %{"italic" => true}),
        Otzel.delete(3)
      ]

      {:ok, dumped} = Delta.dump(delta)
      {:ok, loaded} = Delta.load(dumped)

      # Compare JSON representations since internal struct types may differ
      assert Otzel.json(delta) == Otzel.json(loaded)
    end
  end

  describe "equal?/2" do
    test "equal deltas" do
      a = [Otzel.insert("Hello")]
      b = [Otzel.insert("Hello")]
      assert Delta.equal?(a, b)
    end

    test "different deltas" do
      a = [Otzel.insert("Hello")]
      b = [Otzel.insert("World")]
      refute Delta.equal?(a, b)
    end
  end
end

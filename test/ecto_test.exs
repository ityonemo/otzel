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
      assert {:ok, [insert]} = Delta.cast(json)
      assert insert == Otzel.insert("Hello")
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

      assert delta == [Otzel.insert("Hello"), Otzel.insert(" World", %{"bold" => true})]
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
    test "dumps Otzel operations (Postgrex handles JSON encoding)" do
      delta = [Otzel.insert("Hello"), Otzel.insert(" World", %{"bold" => true})]

      assert {:ok, data} = Delta.dump(delta)
      # dump returns structs directly; Postgrex uses JSON.Encoder to serialize
      assert data == delta
      # Verify JSON encoding produces expected format
      assert JSON.decode!(JSON.encode!(data)) == [
               %{"insert" => "Hello"},
               %{"insert" => " World", "attributes" => %{"bold" => true}}
             ]
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
    test "dump then load preserves delta (simulating database round-trip)" do
      delta = [
        Otzel.insert("Hello "),
        Otzel.insert("World", %{"bold" => true}),
        Otzel.retain(5, %{"italic" => true}),
        Otzel.delete(3)
      ]

      {:ok, dumped} = Delta.dump(delta)
      # Simulate what Postgrex does: JSON encode on write, decode on read
      db_representation = dumped |> JSON.encode!() |> JSON.decode!()
      {:ok, loaded} = Delta.load(db_representation)

      # Compare JSON representations since internal struct types may differ
      assert JSON.encode!(delta) == JSON.encode!(loaded)
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

defmodule OtzelTest.OpTest do
  use ExUnit.Case, async: true

  alias Otzel.Op

  describe ".compose/2 : retain + delete" do
    test "retain + delete" do
      a = Otzel.retain(1)
      b = Otzel.delete(1)

      assert Op.compose(a, b) == {Otzel.delete(1), nil, nil}
    end

    test "retain + bigger delete" do
      a = Otzel.retain(1)
      b = Otzel.delete(2)

      assert Op.compose(a, b) == {Otzel.delete(1), nil, Otzel.delete(1)}
    end

    test "retain + smaller delete" do
      a = Otzel.retain(2)
      b = Otzel.delete(1)

      assert Op.compose(a, b) == {Otzel.delete(1), Otzel.retain(1), nil}
    end

    test "retain with attributes + bigger delete" do
      a = Otzel.retain(1, %{"foo" => true})
      b = Otzel.delete(2)

      assert Op.compose(a, b) == {Otzel.delete(1), nil, Otzel.delete(1)}
    end

    test "retain with attributes + smaller delete" do
      a = Otzel.retain(2, %{"foo" => true})
      b = Otzel.delete(1)

      assert Op.compose(a, b) == {Otzel.delete(1), Otzel.retain(1, %{"foo" => true}), nil}
    end

    test "retain with attributes + bigger delete with attributes" do
      a = Otzel.retain(1, %{"foo" => true})
      b = Otzel.delete(2)

      assert Op.compose(a, b) ==
               {Otzel.delete(1), nil, Otzel.delete(1)}
    end
  end

  describe ".compose/2 : retain + retain" do
    test "retain + retain" do
      a = Otzel.retain(1)
      b = Otzel.retain(1)

      assert Op.compose(a, b) == {Otzel.retain(1), nil, nil}
    end

    test "retain + retain with attributes" do
      a = Otzel.retain(1, %{"foo" => true})
      b = Otzel.retain(1, %{"bar" => true})

      assert Op.compose(a, b) == {Otzel.retain(1, %{"foo" => true, "bar" => true}), nil, nil}
    end

    test "retain + bigger retain" do
      a = Otzel.retain(1)
      b = Otzel.retain(2)

      assert Op.compose(a, b) == {Otzel.retain(1), nil, Otzel.retain(1)}
    end

    test "retain + smaller retain" do
      a = Otzel.retain(2)
      b = Otzel.retain(1)

      assert Op.compose(a, b) == {Otzel.retain(1), Otzel.retain(1), nil}
    end

    test "retain + bigger retain with attributes" do
      a = Otzel.retain(1)
      b = Otzel.retain(2, %{"foo" => true})

      assert Op.compose(a, b) ==
               {Otzel.retain(1, %{"foo" => true}), nil, Otzel.retain(1, %{"foo" => true})}
    end

    test "retain + smaller retain with attributes" do
      a = Otzel.retain(2)
      b = Otzel.retain(1, %{"foo" => true})

      assert Op.compose(a, b) == {Otzel.retain(1, %{"foo" => true}), Otzel.retain(1), nil}
    end

    test "retain + bigger retain both with attributes" do
      a = Otzel.retain(1, %{"bar" => true})
      b = Otzel.retain(2, %{"foo" => true})

      assert Op.compose(a, b) ==
               {Otzel.retain(1, %{"foo" => true, "bar" => true}), nil,
                Otzel.retain(1, %{"foo" => true})}
    end
  end

  describe ".compose/2 : insert + retain" do
    test "insert + retain" do
      a = Otzel.insert("A")
      b = Otzel.retain(1)

      assert Op.compose(a, b) == {Otzel.insert("A"), nil, nil}
    end

    test "insert + smaller retain" do
      a = Otzel.insert("Hello")
      b = Otzel.retain(4)

      assert Op.compose(a, b) == {Otzel.insert("Hell"), Otzel.insert("o"), nil}
    end

    test "insert + bigger retain" do
      a = Otzel.insert("Hello")
      b = Otzel.retain(6)

      assert Op.compose(a, b) == {Otzel.insert("Hello"), nil, Otzel.retain(1)}
    end

    test "insert + retain both with attributes" do
      a = Otzel.insert("A", %{"foo" => true})
      b = Otzel.retain(1, %{"bar" => true})

      assert Op.compose(a, b) == {Otzel.insert("A", %{"foo" => true, "bar" => true}), nil, nil}
    end

    test "insert + smaller retain with attributes" do
      a = Otzel.insert("Hello")
      b = Otzel.retain(4, %{"foo" => true})

      assert Op.compose(a, b) == {Otzel.insert("Hell", %{"foo" => true}), Otzel.insert("o"), nil}
    end

    test "insert + bigger retain with attributes" do
      a = Otzel.insert("Hello")
      b = Otzel.retain(6, %{"foo" => true})

      assert Op.compose(a, b) ==
               {Otzel.insert("Hello", %{"foo" => true}), nil, Otzel.retain(1, %{"foo" => true})}
    end

    test "insert + smaller retain both with attributes" do
      a = Otzel.insert("Hello", %{"foo" => true})
      b = Otzel.retain(4, %{"bar" => true})

      assert Op.compose(a, b) ==
               {Otzel.insert("Hell", %{"foo" => true, "bar" => true}),
                Otzel.insert("o", %{"foo" => true}), nil}
    end

    test "insert + bigger retain both with attributes" do
      a = Otzel.insert("Hello", %{"foo" => true})
      b = Otzel.retain(6, %{"bar" => true})

      assert Op.compose(a, b) ==
               {Otzel.insert("Hello", %{"foo" => true, "bar" => true}), nil,
                Otzel.retain(1, %{"bar" => true})}
    end
  end

  describe ".compose/2 unsupported" do
    test "delete on the left" do
      delete = Otzel.delete(1)
      retain = Otzel.retain(1)
      insert = Otzel.insert("A")

      assert Op.compose(delete, retain) == {nil, nil, nil}
      assert Op.compose(delete, insert) == {nil, nil, nil}
    end

    test "insert on the right" do
      retain = Otzel.retain(1)
      insert = Otzel.insert("A")

      assert Op.compose(retain, insert) == {nil, nil, nil}
      assert Op.compose(insert, insert) == {nil, nil, nil}
    end
  end

  test "insert content regression" do
    a = Otzel.insert([["2" | "B"] | "C3"])

    {front, remains} = Otzel.Op.Insert.take(a, 3)
    assert ~S({"insert":"2BC"}) = JSON.encode!(front)
    assert ~S({"insert":"3"}) = JSON.encode!(remains)
  end
end

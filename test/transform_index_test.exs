defmodule OtzelTest.TransformIndexTest do
  use ExUnit.Case, async: true

  test "insert before position" do
    delta = [Otzel.insert("A")]
    assert Otzel.transform_index(2, delta) == 3
  end

  test "insert after position" do
    delta = [Otzel.retain(2), Otzel.insert("A")]
    assert Otzel.transform_index(1, delta) == 1
  end

  test "insert at position" do
    delta = [Otzel.retain(2), Otzel.insert("A")]
    assert Otzel.transform_index(2, delta, :left) == 2
    assert Otzel.transform_index(2, delta, :right) == 3
  end

  test "delete before position" do
    delta = [Otzel.delete(2)]
    assert Otzel.transform_index(4, delta) == 2
  end

  test "delete after position" do
    delta = [Otzel.retain(4), Otzel.delete(2)]
    assert Otzel.transform_index(2, delta) == 2
  end

  test "delete across position" do
    delta = [Otzel.retain(1), Otzel.delete(4)]
    assert Otzel.transform_index(2, delta) == 1
  end

  test "insert and delete before position" do
    delta = [Otzel.retain(2), Otzel.insert("A"), Otzel.delete(2)]
    assert Otzel.transform_index(4, delta) == 3
  end

  test "insert before and delete across position" do
    delta = [Otzel.retain(2), Otzel.insert("A"), Otzel.delete(4)]
    assert Otzel.transform_index(4, delta) == 3
  end

  test "delete before and delete across position" do
    delta = [Otzel.delete(1), Otzel.retain(1), Otzel.delete(4)]
    assert Otzel.transform_index(4, delta) == 1
  end

  @tag :skip
  test "priority == :left"
end

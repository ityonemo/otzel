defmodule OtzelTest.AttrsTest do
  use ExUnit.Case, async: true
  alias Otzel.Attrs

  @attr %{bold: true, color: "red"}

  test "compose left undefined" do
    assert Attrs.compose(nil, @attr) == @attr
  end

  test "compose right undefined" do
    assert Attrs.compose(@attr, nil) == @attr
  end

  test "both undefined" do
    assert Attrs.compose(nil, nil) == nil
  end

  test "compose missing" do
    param = %{italic: true}

    assert Attrs.compose(@attr, param) == %{
             bold: true,
             italic: true,
             color: "red"
           }
  end

  test "compose overwrite" do
    param = %{bold: false, color: "blue"}

    assert Attrs.compose(@attr, param) == %{
             bold: false,
             color: "blue"
           }
  end

  test "compose remove" do
    param = %{bold: nil}
    assert Attrs.compose(@attr, param) == %{color: "red"}
  end

  test "compose keep removal" do
    param = %{bold: nil}

    assert Attrs.compose(@attr, param, true) == %{
             bold: nil,
             color: "red"
           }
  end

  # TODO divergent behavior vs JS Delta
  test "compose remove to empty" do
    param = %{bold: nil, color: nil}
    assert Attrs.compose(@attr, param) == nil
  end

  test "compose remove missing" do
    param = %{italic: nil}
    assert Attrs.compose(@attr, param) == @attr
  end
end

defmodule OtzelTest do
  use ExUnit.Case, async: true
  doctest Otzel

  alias Otzel.Op.Insert

  import Kernel, except: [=~: 2]
  import OtzelTest.Op, only: [=~: 2]

  describe "slice/3" do
    test "slice across" do
      delta = [
        Otzel.insert("ABC"),
        Otzel.insert("012", %{bold: true}),
        Otzel.insert("DEF")
      ]

      assert Otzel.slice(delta, 1, 7) == [
               Otzel.insert("BC"),
               Otzel.insert("012", %{bold: true}),
               Otzel.insert("DE")
             ]
    end

    test "slice boundaries" do
      delta = [
        Otzel.insert("ABC"),
        Otzel.insert("012", %{bold: true}),
        Otzel.insert("DEF")
      ]

      assert Otzel.slice(delta, 3, 3) == [
               Otzel.insert("012", %{bold: true})
             ]
    end

    test "slice middle" do
      delta = [
        Otzel.insert("ABC"),
        Otzel.insert("012", %{bold: true}),
        Otzel.insert("DEF")
      ]

      assert Otzel.slice(delta, 4, 1) == [
               Otzel.insert("1", %{bold: true})
             ]
    end

    test "slice normal emoji" do
      delta = [Otzel.insert("01🙋45")]
      assert Otzel.slice(delta, 1, 3) == [Otzel.insert("1🙋4")]
    end

    # 🙋‍♂️ is 4 codepoints: 🙋 + ZWJ + ♂ + VS16
    test "slice emoji with zero width joiner" do
      delta = [Otzel.insert("01🙋‍♂️78")]
      # With codepoint counting: "0" + "1" + 4 codepoints + "7" + "8" = 8 total
      assert Otzel.slice(delta, 1, 5) == [Otzel.insert("1🙋‍♂️")]
    end

    # 🙋🏽‍♂️ is 5 codepoints: 🙋 + skin tone + ZWJ + ♂ + VS16
    test "slice emoji with joiner and modifer" do
      delta = [Otzel.insert("01🙋🏽‍♂️90")]
      assert Otzel.slice(delta, 1, 6) == [Otzel.insert("1🙋🏽‍♂️")]
    end

    test "slice with 0 index" do
      delta = [Otzel.insert("12")]
      assert Otzel.slice(delta, 0, 1) == [Otzel.insert("1")]
    end

    # ☹️ is 2 codepoints: ☹ + VS16
    test "slice emoji: codepoint + variation selector" do
      # "01☹️345"
      delta = [Otzel.insert("01\u2639\uFE0F345")]
      assert Otzel.slice(delta, 1, 3) == [Otzel.insert("1☹️")]
      assert Otzel.slice(delta, 1, 4) == [Otzel.insert("1\u2639\uFE0F3")]
    end

    # 🤵🏽 is 2 codepoints: 🤵 + skin tone
    test "slice emoji: codepoint + skin tone modifier" do
      # "01🤵🏽345"
      delta = [Otzel.insert("01\u{1F935}\u{1F3FD}345")]
      assert Otzel.slice(delta, 1, 3) == [Otzel.insert("1\u{1F935}\u{1F3FD}")]
      assert Otzel.slice(delta, 1, 4) == [Otzel.insert("1\u{1F935}\u{1F3FD}3")]
    end

    # 👨‍🏭 is 3 codepoints: 👨 + ZWJ + 🏭
    test "slice emoji: codepoint + ZWJ + codepoint" do
      # "01👨‍🏭345"
      delta = [Otzel.insert("01\u{1F468}\u200D\u{1F3ED}345")]
      assert Otzel.slice(delta, 1, 4) == [Otzel.insert("1\u{1F468}\u200D\u{1F3ED}")]
      assert Otzel.slice(delta, 1, 5) == [Otzel.insert("1\u{1F468}\u200D\u{1F3ED}3")]
    end

    # 🇦🇺 is 2 codepoints: regional indicator A + regional indicator U
    test "slice emoji: flags" do
      # "01🇦🇺345"
      delta = [Otzel.insert("01\u{1F1E6}\u{1F1FA}345")]
      assert Otzel.slice(delta, 1, 3) == [Otzel.insert("1🇦🇺")]
      assert Otzel.slice(delta, 1, 4) == [Otzel.insert("1\u{1F1E6}\u{1F1FA}3")]
    end

    # 🏴󠁧󠁢󠁳󠁣󠁴󠁿 is 7 codepoints: flag + 6 tag characters
    test "slice emoji: tag sequence" do
      # "01🏴󠁧󠁢󠁳󠁣󠁴󠁿345"
      delta = [
        Otzel.insert("01\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}345")
      ]

      assert Otzel.slice(delta, 1, 1) == [Otzel.insert("1")]
      assert Otzel.slice(delta, 1, 8) == [Otzel.insert("1🏴󠁧󠁢󠁳󠁣󠁴󠁿")]

      assert Otzel.slice(delta, 1, 9) == [
               Otzel.insert("1\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}3")
             ]
    end

    # 🚵🏻‍♀️ is 5 codepoints: 🚵 + skin tone + ZWJ + ♀ + VS16
    test "slice complex emoji" do
      # "01🚵🏻‍♀️345"
      delta = [Otzel.insert("01\u{1F6B5}\u{1F3FB}\u{200D}\u{2640}\u{FE0F}345")]

      assert Otzel.slice(delta, 1, 6) == [Otzel.insert("1🚵🏻‍♀️")]

      assert Otzel.slice(delta, 1, 7) == [
               Otzel.insert("1\u{1F6B5}\u{1F3FB}\u{200D}\u{2640}\u{FE0F}3")
             ]
    end
  end

  test "regression" do
    t = [Otzel.insert(" ", %{"" => ""}), Otzel.insert(" ")]
    assert Otzel.take(t, 2) == t
  end

  test "compact test" do
    ot = [Otzel.insert("Hello"), Otzel.insert("World")]
    assert [Otzel.insert("HelloWorld")] =~ Otzel.compact(ot)
  end

  test "compact with binary" do
    ot = [Otzel.insert("Hello", String), Otzel.insert("World", String)]
    assert [Otzel.insert("HelloWorld")] =~ Otzel.compact(ot)
  end

  describe "from_json/2" do
    test "converts string content using configured string module" do
      json = [%{"insert" => "Hello"}]
      [insert] = Otzel.from_json(json)
      assert insert == Otzel.insert("Hello")
    end

    test "uses embed_encoder function for embedded insert content" do
      encoder = fn %{"image" => url} -> {:image, url} end
      json = [%{"insert" => %{"image" => "photo.jpg"}}]

      [insert] = Otzel.from_json(json, embed_encoder: encoder)
      assert insert.content == {:image, "photo.jpg"}
    end

    test "uses embed_encoder {mod, fun} for embedded insert content" do
      defmodule TestEncoder do
        def decode(%{"image" => url}), do: {:image, url}
      end

      json = [%{"insert" => %{"image" => "photo.jpg"}}]

      [insert] = Otzel.from_json(json, embed_encoder: {TestEncoder, :decode})
      assert insert.content == {:image, "photo.jpg"}
    end

    test "uses embed_encoder function for embedded retain target" do
      encoder = fn %{"embed" => ops} -> {:nested, ops} end
      json = [%{"retain" => %{"embed" => [%{"insert" => "a"}]}}]

      [retain] = Otzel.from_json(json, embed_encoder: encoder)
      assert retain.target == {:nested, [%{"insert" => "a"}]}
    end

    test "uses embed_encoder {mod, fun} for embedded retain target" do
      defmodule TestRetainEncoder do
        def decode(%{"embed" => ops}), do: {:nested, ops}
      end

      json = [%{"retain" => %{"embed" => [%{"insert" => "a"}]}}]

      [retain] = Otzel.from_json(json, embed_encoder: {TestRetainEncoder, :decode})
      assert retain.target == {:nested, [%{"insert" => "a"}]}
    end

    test "passes through integer retain targets unchanged" do
      json = [%{"retain" => 5}]
      [retain] = Otzel.from_json(json)
      assert retain.target == 5
    end

    test "passes through delete operations unchanged" do
      json = [%{"delete" => 3}]
      [delete] = Otzel.from_json(json)
      assert delete.count == 3
    end
  end

  describe "Iomemo" do
    alias Otzel.Content.Iomemo

    test "to_string/1" do
      iomemo = Iomemo.new("Hello World")
      assert to_string(iomemo) == "Hello World"
    end

    test "to_string/1 with split content" do
      iomemo = Iomemo.new("Hello World")
      {left, right} = Otzel.Content.take(iomemo, 5)
      assert to_string(left) == "Hello"
      assert to_string(right) == " World"
    end

    test "to_string/1 with concatenated content" do
      a = Iomemo.new("Hello")
      b = Iomemo.new(" World")
      combined = Otzel.Content.concatenate([a, b])
      assert to_string(combined) == "Hello World"
    end
  end
end

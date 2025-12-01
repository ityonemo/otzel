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

    @tag :skip
    test "slice insert object with 0 index" do
      delta = [Otzel.insert(%{"id" => "1"}), Otzel.insert(%{"id" => "2"})]
      assert Otzel.slice(delta, 0, 1) == [Otzel.insert(%{"id" => "1"})]
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

  describe ".split/3" do
    @tag :skip
    test "split at op boundary" do
      # [
      #  Otzel.insert("hello"),
      #  Otzel.insert(%{"code-embed" => []}),
      #  Otzel.insert("world")
      # ]

      # this splitter should split the delta immediately before the first embed
      # assert Otzel.split(
      #         delta,
      #         {fn
      #            Otzel.insert(text), _ when is_binary(text) -> :cont
      #            _, _ -> 0
      #          end, []}
      #       ) ==
      #         {[Otzel.insert("hello")],
      #          [
      #            Otzel.insert(%{"code-embed" => []}),
      #            Otzel.insert("world")
      #          ]}
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
end

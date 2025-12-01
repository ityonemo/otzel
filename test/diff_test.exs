defmodule OtzelTest.DiffTest do
  use ExUnit.Case, async: true

  alias OtzelTest.Op

  import Kernel, except: [=~: 2]
  import OtzelTest.Op, only: [=~: 2]

  describe ".diff/2 (basic)" do
    test "insert" do
      a = [Otzel.insert("A")]
      b = [Otzel.insert("AB")]

      assert [Otzel.retain(1), Otzel.insert("B")] == Otzel.diff(a, b)
      assert Otzel.compose(a, Otzel.diff(a, b)) =~ b
    end

    test "delete" do
      a = [Otzel.insert("AB")]
      b = [Otzel.insert("A")]

      assert [Otzel.retain(1), Otzel.delete(1)] == Otzel.diff(a, b)
      assert Otzel.compose(a, Otzel.diff(a, b)) =~ b
    end

    test "retain" do
      a = [Otzel.insert("A")]
      b = [Otzel.insert("A")]

      assert [] == Otzel.diff(a, b)
      assert Otzel.compose(a, Otzel.diff(a, b)) == b
    end

    test "format" do
      a = [Otzel.insert("A")]
      b = [Otzel.insert("A", %{"bold" => true})]

      assert [Otzel.retain(1, %{"bold" => true})] == Otzel.diff(a, b)
      assert Otzel.compose(a, Otzel.diff(a, b)) == b
    end

    test "object attributes" do
      a = [Otzel.insert("A", %{"font" => %{"family" => "Helvetica", "size" => "15px"}})]
      b = [Otzel.insert("A", %{"font" => %{"family" => "Helvetica", "size" => "15px"}})]

      assert [] == Otzel.diff(a, b)
      assert Otzel.compose(a, Otzel.diff(a, b)) == b
    end

    alias OtzelTest.Content.Integer

    @tag :skip
    test "embed integer match" do
      a = [Otzel.insert(Integer.new(1))]
      b = [Otzel.insert(Integer.new(1))]

      assert [] == Otzel.diff(a, b)
      assert Otzel.compose(a, Otzel.diff(a, b)) == b
    end

    @tag :skip
    test "embed integer mismatch" do
      a = [Otzel.insert(Integer.new(1))]
      b = [Otzel.insert(Integer.new(2))]

      assert [Otzel.delete(1), Otzel.insert(Integer.new(2))] == Otzel.diff(a, b)
      assert Otzel.compose(a, Otzel.diff(a, b)) == b
    end

    alias OtzelTest.Content.Image

    @tag :skip
    test "embed object match" do
      a = [Otzel.insert(Image.new("http://example.com"))]
      b = [Otzel.insert(Image.new("http://example.com"))]

      assert [] == Otzel.diff(a, b)
      assert Otzel.compose(a, Otzel.diff(a, b)) == b
    end

    @tag :skip
    test "embed object mismatch" do
      a = [Otzel.insert(Image.new("http://example.com", "overwrite"))]
      b = [Otzel.insert(Image.new("http://example.com"))]

      assert [Otzel.delete(1), Otzel.insert(Image.new("http://example.com"))] ==
               Otzel.diff(a, b)

      assert Otzel.compose(a, Otzel.diff(a, b)) == b
    end

    @tag :skip
    test "embed object change" do
      a = [Otzel.insert(Image.new("http://example.com"))]
      b = [Otzel.insert(Image.new("http://example.org"))]

      assert [Otzel.delete(1), Otzel.insert(Image.new("http://example.org"))] == Otzel.diff(a, b)
      assert Otzel.compose(a, Otzel.diff(a, b)) == b
    end

    test "error on non-documents" do
      a = [Otzel.insert("A")]
      b = [Otzel.retain(1), Otzel.insert("B")]

      assert_raise RuntimeError, fn -> Otzel.diff(a, b) end
      assert_raise RuntimeError, fn -> Otzel.diff(b, a) end
    end

    test "inconvenient indices" do
      a = [Otzel.insert("12", %{"bold" => true}), Otzel.insert("34", %{"italic" => true})]
      b = [Otzel.insert("123", %{"color" => "red"})]

      assert [
               Otzel.retain(2, %{"bold" => nil, "color" => "red"}),
               Otzel.retain(1, %{"italic" => nil, "color" => "red"}),
               Otzel.delete(1)
             ] == Otzel.diff(a, b)

      assert Otzel.compose(a, Otzel.diff(a, b)) =~ b
    end

    test "combination" do
      a = [Otzel.insert("Bad", %{"color" => "red"}), Otzel.insert("cat", %{"color" => "blue"})]
      b = [Otzel.insert("Good", %{"bold" => true}), Otzel.insert("dog", %{"italic" => true})]

      # semantic cleanup simplifies this diff
      assert [
               Otzel.delete(6),
               Otzel.insert("Good", %{"bold" => true}),
               Otzel.insert("dog", %{"italic" => true})
             ] =~ Otzel.diff(a, b)

      assert Otzel.compose(a, Otzel.diff(a, b)) =~ b
    end
  end

  describe ".diff/2 (custom embeds)" do
    test "equal strings" do
      a = [Otzel.insert("A")]
      b = [Otzel.insert("A")]

      assert [] == Otzel.diff(a, b)
      assert Otzel.compose(a, Otzel.diff(a, b)) == b
    end

    @tag :skip
    test "equal embeds" do
      a = [Otzel.insert(Op.embed(Otzel.insert("hello")))]
      b = [Otzel.insert(Op.embed(Otzel.insert("hello")))]

      assert [] == Otzel.diff(a, b)
      assert Otzel.compose(a, Otzel.diff(a, b)) == b
    end

    @tag :skip
    test "basic embed diff" do
      a = [Otzel.insert(Op.embed(Otzel.insert("hello world")))]
      b = [Otzel.insert(Op.embed(Otzel.insert("goodbye world")))]

      assert [
               Otzel.retain(
                 Op.embed([
                   Otzel.delete(5),
                   Otzel.insert("goodbye")
                 ])
               )
             ] =~ Otzel.diff(a, b)

      assert Otzel.compose(a, Otzel.diff(a, b)) =~ b
    end

    @tag :skip
    test "embed diff with attribute changes" do
      a = [
        Otzel.insert(
          Op.embed(Otzel.insert("hello world")),
          %{"bold" => true, "color" => "red"}
        )
      ]

      b = [
        Otzel.insert(
          Op.embed(Otzel.insert("goodbye world")),
          %{"italic" => true, "color" => "yellow"}
        )
      ]

      assert [
               Otzel.retain(
                 Op.embed([
                   Otzel.delete(5),
                   Otzel.insert("goodbye")
                 ]),
                 %{
                   "bold" => nil,
                   "italic" => true,
                   "color" => "yellow"
                 }
               )
             ] =~ Otzel.diff(a, b)

      assert Otzel.compose(a, Otzel.diff(a, b)) =~ b
    end

    alias OtzelTest.Content.Quote

    @tag :skip
    test "different embeds" do
      a = [Otzel.insert(Op.embed(Otzel.insert("hello world")))]
      b = [Otzel.insert(Quote.new(Otzel.insert("goodbye world")))]

      assert [
               Otzel.delete(1),
               Otzel.insert(Quote.new(Otzel.insert("goodbye world")))
             ] == Otzel.diff(a, b)

      assert Otzel.compose(a, Otzel.diff(a, b)) == b
    end

    @tag :skip
    test "embeds without handler diff attributes if equal" do
      a = [Otzel.insert(Quote.new(Otzel.insert("hello world")), %{"author" => "A"})]
      b = [Otzel.insert(Quote.new(Otzel.insert("hello world")), %{"author" => "B"})]

      assert [
               Otzel.retain(1, %{"author" => "B"})
             ] == Otzel.diff(a, b)

      assert Otzel.compose(a, Otzel.diff(a, b)) == b
    end

    @tag :skip
    test "embeds without handler replaces whole operation if different content" do
      a = [Otzel.insert(Quote.new(Otzel.insert("foo")), %{"author" => "A"})]
      b = [Otzel.insert(Quote.new(Otzel.insert("bar")), %{"author" => "B"})]

      assert [
               Otzel.delete(1),
               Otzel.insert(Quote.new(Otzel.insert("bar")), %{"author" => "B"})
             ] == Otzel.diff(a, b)
    end
  end

  test "regression-1" do
    text_a = [Otzel.insert("AB", %{"A" => "B"})]
    text_b = [Otzel.insert("AC")]

    diff = Otzel.diff(text_a, text_b)

    assert Otzel.compact(text_b) =~
             text_a
             |> Otzel.compose(diff)
             |> Otzel.compact()
  end

  test "regression-2" do
    text_a = [
      Otzel.insert("A", %{"A" => "B"}),
      Otzel.insert("B"),
      Otzel.insert("C")
    ]

    text_b = [Otzel.insert("ABD")]

    diff = Otzel.diff(text_a, text_b)

    assert Otzel.compact(text_b) =~
             text_a
             |> Otzel.compose(diff)
             |> Otzel.compact()
  end

  test "regression-3: simple hello/world with attrs" do
    alias Otzel.Content.Iomemo

    text_a = [%Otzel.Op.Insert{content: Iomemo.new("hello"), attrs: %{"bold" => true}}]
    text_b = [%Otzel.Op.Insert{content: Iomemo.new("world"), attrs: nil}]

    diff = Otzel.diff(text_a, text_b)

    assert Otzel.compact(text_b) =~
             text_a
             |> Otzel.compose(diff)
             |> Otzel.compact()
  end

  test "regression-4: long text_a to short text_b" do
    alias Otzel.Content.Iomemo

    # Simplified version of failing property test
    text_a = [
      %Otzel.Op.Insert{content: Iomemo.new("T2z|_s`[s3rt>.LlL"), attrs: nil},
      %Otzel.Op.Insert{content: Iomemo.new("hello"), attrs: %{"u" => "PTdwQsV"}}
    ]
    text_b = [%Otzel.Op.Insert{content: Iomemo.new("Bki"), attrs: nil}]

    diff = Otzel.diff(text_a, text_b)

    assert Otzel.compact(text_b) =~
             text_a
             |> Otzel.compose(diff)
             |> Otzel.compact()
  end

  test "regression-5: exact failing property test case" do
    alias Otzel.Content.Iomemo

    # Exact case from property test with seed 320798
    text_a = [
      %Otzel.Op.Insert{content: %Iomemo{s: ["T2z|_s`[s3r" | "t>.LlL"], l: {17, [11 | 6]}}, attrs: nil},
      %Otzel.Op.Insert{content: %Iomemo{s: "𐨃򟍾𧙝񼈞𭉃", l: 5}, attrs: %{"u" => "PTdwQsV"}},
      %Otzel.Op.Insert{content: %Iomemo{s: "t", l: 1}, attrs: %{"kUS" => "ce"}},
      %Otzel.Op.Insert{content: %Iomemo{s: [["l ,fs:D" | " d"] | "z"], l: {10, [{9, [7 | 2]} | 1]}}, attrs: %{"6j6tw8OwURE" => "OYo"}},
      %Otzel.Op.Insert{content: %Iomemo{s: "Y[Wif6!.@b{C", l: 12}, attrs: nil},
      %Otzel.Op.Insert{content: %Iomemo{s: "taG`V%yZjNu", l: 11}, attrs: %{"n" => "hoqH"}},
      %Otzel.Op.Insert{content: %Iomemo{s: [["@x" | "Thm-/6G"], "kKh[?S<A\\h" | ">[4L*qRD"], l: {27, [{9, [2 | 7]}, 10 | 8]}}, attrs: %{"uxnjW8cL" => ""}},
      %Otzel.Op.Insert{content: %Iomemo{s: ">Q{Jq6d", l: 7}, attrs: nil},
      %Otzel.Op.Insert{content: %Iomemo{s: "\\|OW,dmi ~`", l: 11}, attrs: nil},
      %Otzel.Op.Insert{content: %Iomemo{s: "me|Bp7H", l: 7}, attrs: %{"" => "USBQgeWS"}},
      %Otzel.Op.Insert{content: %Iomemo{s: [[["P!{\"^nU?V-e-m" | "><eB/AK}AM+"], "ocI7^']TMWS+" | "a4a.T\"rOAX8)"], "Neo>T7Y-BA", "Uc]7&y\\6-c)it" | "򦆝󲌷򌝶󡭟񺂂񈗃񏤰󄝉"], l: {79, [{48, [{24, [13 | 11]}, 12 | 12]}, 10, 13 | 8]}}, attrs: nil},
      %Otzel.Op.Insert{content: %Iomemo{s: "%T79+g<PSEl", l: 11}, attrs: nil}
    ]

    text_b = [%Otzel.Op.Insert{content: %Iomemo{s: "Bki", l: 3}, attrs: nil}]

    diff = Otzel.diff(text_a, text_b)

    assert Otzel.compact(text_b) =~
             text_a
             |> Otzel.compose(diff)
             |> Otzel.compact()
  end

  use ExUnitProperties
  alias Otzel.Streamed
  alias Otzel.Content

  for type <- [String, Otzel.Content.Binmemo] do
    property "compose for #{type}" do
      check all(
              a <- Streamed.insert_ot(),
              b <- Streamed.insert_ot(),
              max_run_time: 1000
            ) do
        a_remapped = Content.remap_inserts(a, unquote(type))
        b_remapped = Content.remap_inserts(b, unquote(type))

        assert Otzel.diff(a_remapped, b_remapped) =~ Otzel.diff(a, b)
      end
    end
  end
end

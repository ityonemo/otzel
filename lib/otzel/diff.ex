defmodule Otzel.Diff do
  @moduledoc """
  Text diffing utilities for Otzel.

  This module computes the difference between two binary strings, returning
  a list of OT operations (Insert, Retain, Delete) that transform the first
  string into the second.

  The implementation uses a half-match optimization for efficient diffing
  of large texts with common substrings.
  """

  alias Otzel.Op
  alias Otzel.Op.Insert
  alias Otzel.Op.Retain
  alias Otzel.Op.Delete

  @doc """
  Compute the difference between two binary texts.
  """
  @spec diff(binary(), binary(), module) :: [Op.t()]
  def diff(<<>>, <<>>, _module), do: []

  def diff(text1, text2, _module) when text1 == text2 do
    [%Retain{target: Otzel._codepoints(text1)}]
  end

  def diff(text1, text2, module) do
    {prefix, m_text1, m_text2, suffix} = split_pre_and_suffix(text1, text2)

    diffs = compute_diff(m_text1, m_text2, module)

    diffs1 =
      case suffix do
        <<>> -> diffs
        _ -> diffs ++ [%Retain{target: Otzel._codepoints(suffix)}]
      end

    diffs2 =
      case prefix do
        <<>> -> diffs1
        _ -> [%Retain{target: Otzel._codepoints(prefix)} | diffs1]
      end

    cleanup_merge(diffs2)
  end

  defp split_pre_and_suffix(text1, text2) do
    prefix = common_prefix(text1, text2)
    prefix_len = byte_size(prefix)

    <<_::binary-size(prefix_len), tail_text1::binary>> = text1
    <<_::binary-size(prefix_len), tail_text2::binary>> = text2

    suffix = common_suffix(tail_text1, tail_text2)
    suffix_len = byte_size(suffix)

    middle_text1 = :binary.part(tail_text1, 0, byte_size(tail_text1) - suffix_len)
    middle_text2 = :binary.part(tail_text2, 0, byte_size(tail_text2) - suffix_len)

    {prefix, middle_text1, middle_text2, suffix}
  end

  defp cleanup_merge(diffs), do: diffs

  # This assumes text1 and text2 don't have a common prefix
  defp compute_diff(<<>>, new_text, module) do
    [%Insert{content: module.new(new_text)}]
  end

  defp compute_diff(old_text, <<>>, _module) do
    [%Delete{count: Otzel._codepoints(old_text)}]
  end

  defp compute_diff(old_text, new_text, module) do
    old_st_new = byte_size(old_text) < byte_size(new_text)

    {short_text, long_text} =
      case old_st_new do
        true -> {old_text, new_text}
        false -> {new_text, old_text}
      end

    case :binary.match(long_text, short_text) do
      {start, length} ->
        <<pre::binary-size(start), _::binary-size(length), suf::binary>> = long_text
        op = diff_op(old_st_new, module)
        [op.(pre), %Retain{target: Otzel._codepoints(short_text)}, op.(suf)]

      :nomatch ->
        if single_char?(short_text) do
          [%Delete{count: Otzel._codepoints(old_text)}, %Insert{content: module.new(new_text)}]
        else
          try_half_match(old_text, new_text, module)
        end
    end
  end

  defp diff_op(true, module), do: fn text -> %Insert{content: module.new(text)} end
  defp diff_op(false, _module), do: fn text -> %Delete{count: Otzel._codepoints(text)} end

  defp single_char?(<<>>), do: false
  defp single_char?(<<_c::utf8>>), do: true
  defp single_char?(_), do: false

  # Check if we can do a half-match diff, if not, try line or bisect diff.
  defp try_half_match(old_text, new_text, module) do
    case half_match(old_text, new_text) do
      {:half_match, a1, a2, b1, b2, common} ->
        diffs1 = diff(a1, b1, module)
        diffs2 = diff(a2, b2, module)
        diffs1 ++ [%Retain{target: Otzel._codepoints(common)} | diffs2]

      nil ->
        compute_diff1(old_text, new_text, module)
    end
  end

  # Check if we can do a half-match diff, returns nil if it is not advantageous.
  defp half_match(a, b) do
    a_gt_b = byte_size(a) > byte_size(b)

    {short, long} =
      case a_gt_b do
        true -> {b, a}
        false -> {a, b}
      end

    if text_smaller_than?(long, 4) or byte_size(short) * 2 < byte_size(long) do
      # No point in looking.
      nil
    else
      # Note: this could split through a utf8 byte sequence.
      hm1 = half_match_i(long, short, div(byte_size(long) + 3, 4))
      hm2 = half_match_i(long, short, div(byte_size(long) + 1, 2))

      # Select the longest half-match.
      hm =
        case {hm1, hm2} do
          {nil, nil} ->
            nil

          {nil, _} ->
            hm2

          {_, nil} ->
            hm1

          {{:half_match, _, _, _, _, c1}, {:half_match, _, _, _, _, c2}}
          when byte_size(c1) > byte_size(c2) ->
            hm1

          {_, _} ->
            hm2
        end

      # Swap values if A was smaller than B
      case hm do
        nil ->
          nil

        {:half_match, t1a, t1b, t2a, t2b, mid_common} ->
          case a_gt_b do
            true -> hm
            false -> {:half_match, t2a, t2b, t1a, t1b, mid_common}
          end
      end
    end
  end

  # Find the best common overlap at location i.
  defp half_match_i(long, short, i) do
    {new_i, seed} = seed(long, i)

    case seed do
      <<>> ->
        nil

      _ ->
        best_common(long, short, seed, new_i, 0, nil, nil, nil, nil, <<>>)
    end
  end

  # Find the best common overlap inside two texts.
  defp best_common(
         long,
         short,
         seed,
         seed_loc,
         start,
         best_long_a,
         best_long_b,
         best_short_a,
         best_short_b,
         best_common
       ) do
    # Check if we can find a match for seed inside the short text.
    case :binary.match(short, seed, scope: {start, byte_size(short) - start}) do
      :nomatch ->
        if byte_size(best_common) * 2 >= byte_size(long) do
          {:half_match, best_long_a, best_long_b, best_short_a, best_short_b, best_common}
        else
          nil
        end

      {match_start, _} ->
        # Because the seed is already at utf-8 boundaries this will work.
        <<long_pre::binary-size(seed_loc), long_post::binary>> = long
        <<short_pre::binary-size(match_start), short_post::binary>> = short

        # Note: This is a split on a utf8-char boundary.
        suffix = common_suffix(long_pre, short_pre)
        prefix = common_prefix(long_post, short_post)

        prefix_size = byte_size(prefix)
        suffix_size = byte_size(suffix)

        if byte_size(best_common) < prefix_size + suffix_size do
          # We have a new best common match
          new_best_common = <<suffix::binary, prefix::binary>>

          a = seed_loc - suffix_size
          <<new_best_long_a::binary-size(a), _::binary>> = long_pre
          <<_::binary-size(prefix_size), new_best_long_b::binary>> = long_post

          b = match_start - suffix_size
          <<new_best_short_a::binary-size(b), _::binary>> = short_pre
          <<_::binary-size(prefix_size), new_best_short_b::binary>> = short_post

          best_common(
            long,
            short,
            seed,
            seed_loc,
            next_char(short, match_start),
            new_best_long_a,
            new_best_long_b,
            new_best_short_a,
            new_best_short_b,
            new_best_common
          )
        else
          best_common(
            long,
            short,
            seed,
            seed_loc,
            next_char(short, match_start),
            best_long_a,
            best_long_b,
            best_short_a,
            best_short_b,
            best_common
          )
        end
    end
  end

  # Return the position of the next character.
  defp next_char(bin, pos) do
    <<_::binary-size(pos), c::utf8, _rest::binary>> = bin
    # The next char is at binary position...
    pos + byte_size(<<c::utf8>>)
  end

  defp seed(long, start) do
    seed_size = div(byte_size(long), 4)

    # Note, need to split on utf8 character boundary here.
    <<_pre::binary-size(start), seed::binary-size(seed_size), _post::binary>> = long

    # Utf-8 repair the seed's head and tail.
    {pre, seed1} = repair_head(seed)
    {seed2, _} = repair_tail(seed1)

    # return the start position of the seed and the seed itself.
    {start - byte_size(pre), seed2}
  end

  # Line diff / bisect fallback
  defp compute_diff1(text1, text2, module) do
    # For now, fall back to simple delete + insert
    # TODO: implement diff_linemode and diff_bisect
    [%Delete{count: Otzel._codepoints(text1)}, %Insert{content: module.new(text2)}]
  end

  # Return true iff the text is smaller than specified (in codepoints)
  defp text_smaller_than?(_, 0), do: false
  defp text_smaller_than?(<<>>, _size), do: true

  defp text_smaller_than?(<<_c::utf8, rest::binary>>, size) when size > 0,
    do: text_smaller_than?(rest, size - 1)

  defp text_smaller_than?(<<_c, rest::binary>>, size) when size > 0,
    do: text_smaller_than?(rest, size - 1)

  # Return the common prefix of text1 and text2 (utf8 aware)
  defp common_prefix(text1, text2) do
    length = :binary.longest_common_prefix([text1, text2])
    prefix = :binary.part(text1, 0, length)

    # Utf-8 repair the tail of the prefix. It could contain a half utf-8 char.
    {prefix1, _} = repair_tail(prefix)
    prefix1
  end

  # Return the common suffix of text1 and text2 (utf8 aware)
  defp common_suffix(text1, text2) do
    length = :binary.longest_common_suffix([text1, text2])
    suffix = :binary.part(text1, byte_size(text1), -length)

    # Utf-8 repair the head of the suffix. Could contain a half utf8 char
    {_, suffix1} = repair_head(suffix)
    suffix1
  end

  # Checks the trailing bytes for utf8 prefix bytes.
  defp repair_tail(<<>>), do: {<<>>, <<>>}

  defp repair_tail(bin) do
    size = byte_size(bin)
    size1 = size - 1
    size2 = size - 2
    size3 = size - 3
    size4 = size - 4

    case bin do
      # Valid 1-byte
      <<_::binary-size(size1), 0::1, _a::7>> ->
        {bin, <<>>}

      # Invalid 1-byte
      <<pre::binary-size(size1), 0b110::3, a::5>> ->
        {pre, <<0b110::3, a::5>>}

      <<pre::binary-size(size1), 0b1110::4, a::4>> ->
        {pre, <<0b1110::4, a::4>>}

      <<pre::binary-size(size1), 0b11110::5, a::3>> ->
        {pre, <<0b11110::5, a::3>>}

      # Valid 2-byte ending
      <<_::binary-size(size2), 0b110::3, _a::5, 0b10::2, _b::6>> ->
        {bin, <<>>}

      # Invalid 2-byte ending
      <<pre::binary-size(size2), 0b1110::4, a::4, 0b10::2, b::6>> ->
        {pre, <<0b1110::4, a::4, 0b10::2, b::6>>}

      <<pre::binary-size(size2), 0b11110::5, a::3, 0b10::2, b::6>> ->
        {pre, <<0b11110::5, a::3, 0b10::2, b::6>>}

      # Valid 3-byte ending
      <<_::binary-size(size3), 0b1110::4, _a::4, 0b10::2, _b::6, 0b10::2, _c::6>> ->
        {bin, <<>>}

      # Invalid 3-byte ending
      <<pre::binary-size(size3), 0b11110::5, a::3, 0b10::2, b::6, 0b10::2, c::6>> ->
        {pre, <<0b11110::5, a::3, 0b10::2, b::6, 0b10::2, c::6>>}

      # Valid 4-byte ending
      <<_::binary-size(size4), 0b11110::5, _a::3, 0b10::2, _b::6, 0b10::2, _c::6, 0b10::2, _d::6>> ->
        {bin, <<>>}

      # Illegal utf-8 sequence - can't repair it, just return
      _ ->
        {bin, <<>>}
    end
  end

  # Checks the beginning of a binary and strips of partial utf-8 encoded bytes.
  defp repair_head(<<>>), do: {<<>>, <<>>}
  # valid 1-byte beginning
  defp repair_head(<<0::1, _a::7, _rest::binary>> = bin), do: {<<>>, bin}
  # valid 4-byte beginning
  defp repair_head(
         <<0b11110::5, _a::3, 0b10::2, _b::6, 0b10::2, _c::6, 0b10::2, _d::6, _rest::binary>> =
           bin
       ),
       do: {<<>>, bin}

  # valid 3-byte beginning
  defp repair_head(<<0b1110::4, _a::4, 0b10::2, _b::6, 0b10::2, _c::6, _rest::binary>> = bin),
    do: {<<>>, bin}

  # invalid 3-byte beginning
  defp repair_head(<<0b10::2, a::6, 0b10::2, b::6, 0b10::2, c::6, rest::binary>>),
    do: {<<0b10::2, a::6, 0b10::2, b::6, 0b10::2, c::6>>, rest}

  # valid 2-byte beginning
  defp repair_head(<<0b110::3, _a::5, 0b10::2, _b::6, _rest::binary>> = bin), do: {<<>>, bin}
  # invalid 2-byte beginnings
  defp repair_head(<<0b10::2, a::6, 0b10::2, b::6, rest::binary>>),
    do: {<<0b10::2, a::6, 0b10::2, b::6>>, rest}

  # invalid 1-byte beginning
  defp repair_head(<<0b10::2, a::6, rest::binary>>), do: {<<0b10::2, a::6>>, rest}
  # Illegal sequence, can't repair it.
  defp repair_head(bin), do: {<<>>, bin}
end

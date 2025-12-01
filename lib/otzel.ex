defmodule Otzel do
  @moduledoc """
  Otzel is an Elixir library for Operational Transformation (OT).

  Operational Transformation is a technique for maintaining consistency in collaborative
  editing systems. When multiple users edit a shared document simultaneously, OT ensures
  that all users see the same final result regardless of the order in which edits are received.

  ## The Delta Format

  Otzel implements the [Delta format](https://quilljs.com/docs/delta/), representing documents
  and changes as lists of operations. A delta is simply a list of `t:Otzel.Op.t/0` operations.

  There are three types of operations:

  - **Insert** (`Otzel.Op.Insert`) - Adds new content
  - **Retain** (`Otzel.Op.Retain`) - Keeps existing content (optionally modifying attributes)
  - **Delete** (`Otzel.Op.Delete`) - Removes content

  ## Documents vs Changes

  The same delta format represents both:

  - **Documents**: Deltas consisting only of insert operations
  - **Changes**: Deltas that may include retain and delete operations

  ## Example Usage

      # Create a document
      doc = [Otzel.insert("Hello World")]

      # Create a change that makes "World" bold
      change = [Otzel.retain(6), Otzel.retain(5, %{"bold" => true})]

      # Apply the change
      new_doc = Otzel.compose(doc, change)

  ## Core Operations

  - `compose/2` - Combine two deltas into one
  - `transform/3` - Adjust a delta for concurrent edits
  - `invert/2` - Create an undo delta
  - `diff/2` - Compute the delta between two documents

  ## Configuration

  The default string module can be configured:

      config :otzel, :string_module, Otzel.Content.Iomemo

  """

  alias Otzel.Op

  @typedoc """
  A delta is a list of operations representing a document or change.

  Documents are deltas containing only insert operations.
  Changes may contain insert, retain, and delete operations.
  """
  @type t :: [Op.t()]

  @typedoc """
  Priority determines which concurrent operation "wins" during transformation.

  - `:left` - The first operation has priority
  - `:right` - The second operation has priority
  """
  @type priority :: :left | :right

  alias Otzel.Attrs
  alias Otzel.Content
  alias Otzel.Op.Insert
  alias Otzel.Op.Delete
  alias Otzel.Op.Retain

  @spec size(t) :: non_neg_integer
  @doc """
  Returns the total size of the operations in the transformation.
  For strings, the size is the number of graphemes in the string.

  ```elixir
  iex> alias Otzel.Op.{Insert, Retain}
  iex> Otzel.size([%Insert{content: "Hello"}])
  5
  iex> Otzel.size([%Insert{content: "Howdy🤠!"}])
  7
  iex> Otzel.size([%Insert{content: "Hello"}, %Retain{target: 3}])
  8
  ```
  """
  def size(ops), do: Enum.sum_by(ops, &Op.size/1)

  @spec slice(t, start :: non_neg_integer, count :: non_neg_integer) :: t
  @doc """
  Returns a slice of operations starting from `start` with a given count
  ```elixir
  iex> alias Otzel.Op.{Insert, Retain}
  iex> Otzel.slice([%Insert{content: "Hello"}, %Retain{target: 3}], 2, 5)
  [%Insert{content: "llo"}, %Retain{target: 2}]
  ```
  """
  def slice(ops, start, count) do
    ops
    |> seek(start)
    |> take(count)
  end

  @type split_fun :: (Op.t() -> :cont | non_neg_integer)
  @type split_fun_ctx :: (Op.t(), context :: term ->
                            :cont | {:cont, context :: term} | non_neg_integer)

  @spec split(t, non_neg_integer | split_fun | {split_fun_ctx, context :: term}) :: {t, t}
  @doc """
  splits a transformation into two parts at the supplied index

  ```elixir
  iex> alias Otzel.Op.{Insert, Retain}
  iex> Otzel.split([%Insert{content: "Hello"}, %Retain{target: 3}], 2)
  {[%Insert{content: "He"}], [%Insert{content: "llo"}, %Retain{target: 3}]}
  ```
  """
  def split(ops, fun) when is_function(fun, 1), do: {split(ops, {fn op, _ -> fun.(op) end, []})}

  def split(ops, {fun, ctx}) when is_function(fun, 2) do
    split_fun(ops, fun, ctx, [])
  end

  def split(ops, start), do: split(ops, start, [], :fwd)

  # split, but returns the front part in reverse order.
  def split_rev(ops, start), do: split(ops, start, [], :rev)

  defp split(ops, 0, so_far, :fwd), do: {Enum.reverse(so_far), ops}
  defp split(ops, 0, so_far, :rev), do: {so_far, ops}

  defp split([head | rest], count, so_far, direction) do
    case Op.size(head) do
      size when size <= count ->
        split(rest, count - size, [head | so_far], direction)

      _size_bigger ->
        {part, more} = Op.take(head, count)

        front =
          case direction do
            :fwd -> Enum.reverse([part | so_far])
            :rev -> [part | so_far]
          end

        {front, [more | rest]}
    end
  end

  defp split([], _, so_far, :fwd), do: {Enum.reverse(so_far), []}
  defp split([], _, so_far, :rev), do: {so_far, []}

  defp split_fun([head | rest] = ops, fun, ctx, so_far) do
    case fun.(head, ctx) do
      :cont ->
        split_fun(rest, fun, ctx, [head | so_far])

      {:cont, new_ctx} ->
        split_fun(rest, fun, new_ctx, [head | so_far])

      count ->
        split(ops, count, so_far, :fwd)
    end
  end

  @spec take(t, non_neg_integer) :: t
  @doc """
  Takes the first `count` operations from the list of operations.

  ```elixir
  iex> alias Otzel.Op.{Insert, Retain}
  iex> Otzel.take([%Insert{content: "Hello"}, %Retain{target: 3}], 6)
  [%Insert{content: "Hello"}, %Retain{target: 1}]
  ```
  """
  def take(ops, count, so_far \\ [])

  def take([head | rest], count, so_far) do
    case Op.size(head) do
      size when size < count ->
        take(rest, count - size, [head | so_far])

      size when size == count ->
        Enum.reverse([head | so_far])

      _bigger ->
        {part, _} = Op.take(head, count)
        Enum.reverse([part | so_far])
    end
  end

  def take([], _, so_far), do: Enum.reverse(so_far)

  @spec push(t, Op.t() | nil) :: t
  defp push(delta, nil), do: delta
  defp push([], op), do: [op]

  defp push([head | rest], op) do
    if merged = Op.merge_into(head, op) do
      [merged | rest]
    else
      [op, head | rest]
    end
  end

  @spec seek(t, non_neg_integer) :: t
  @doc """
  Takes operations beyond `count` operations from the list of operations.

  ```elixir
  iex> alias Otzel.Op.{Insert, Retain}
  iex> Otzel.seek([%Insert{content: "Hello"}, %Retain{target: 3}], 3)
  [%Insert{content: "lo"}, %Retain{target: 3}]
  ```
  """
  def seek(ops, 0), do: ops

  def seek([head | rest], start) do
    case Op.size(head) do
      size when size <= start ->
        seek(rest, start - size)

      _bigger ->
        {_, part} = Op.take(head, start)
        [part | rest]
    end
  end

  def seek([], _), do: []

  @spec compose(t, t) :: t
  @doc """
  Composes two deltas into a single delta with the same effect as applying them sequentially.

  Given deltas A and B, `compose(A, B)` returns a delta C such that applying C to a document
  has the same effect as applying A then B.

  ## Examples

      iex> doc = [Otzel.insert("Hello")]
      iex> change = [Otzel.retain(5), Otzel.insert(" World")]
      iex> result = Otzel.compose(doc, change)
      iex> Otzel.json(result)
      [%{"insert" => "Hello World"}]

      iex> a = [Otzel.insert("abc")]
      iex> b = [Otzel.retain(1), Otzel.delete(1), Otzel.retain(1)]
      iex> Otzel.json(Otzel.compose(a, b))
      [%{"insert" => "ac"}]

  ## Properties

  Compose is associative: `compose(compose(a, b), c) == compose(a, compose(b, c))`
  """
  def compose(left, right) do
    compose(left, right, [])
  end

  defp compose([], [], so_far), do: finalize(so_far, [])

  defp compose([], rest, so_far) do
    rest
    |> Enum.reverse(so_far)
    |> finalize([])
  end

  defp compose(rest, [], so_far) do
    rest
    |> Enum.reverse(so_far)
    |> finalize([])
  end

  defp compose([head1 | rest1], [head2 | rest2], so_far) do
    # BREAK THIS APART.
    {op, t1, t2} =
      case {head1, head2} do
        {_, %Insert{}} ->
          {head2, [head1 | rest1], rest2}

        {%Delete{}, _} ->
          {head1, rest1, [head2 | rest2]}

        _ ->
          {composed, unused1, unused2} = Op.compose(head1, head2)
          {composed, push(rest1, unused1), push(rest2, unused2)}
      end

    # THIS IS NOT THE RIGHT OPERATION.
    compose(t1, t2, [op | so_far])
  end

  @spec invert(t, t) :: t
  @doc """
  Computes an inverted transformation transformation, that has the opposite effect against a base transformation.

  Note that the following invariant holds for `base` a list of inserts and `change` a transformation with retains and
  deletes fewer than the size of `base`:

  `base == compose(compose(base, change), compose(invert(change, base)))`

  ```elixir
  iex> alias Otzel.Op.{Insert, Retain, Delete}
  iex> Otzel.invert([%Retain{target: 6, attrs: %{"bold" => true}}, %Delete{count: 5}, %Insert{content: "!"}], [%Insert{content: "Hello\\nWorld"}])
  [
    %Retain{target: 6, attrs: %{"bold" => nil}},
    %Insert{content: "World"},
    %Delete{count: 1}
  ]
  ```
  """
  def invert(change, base), do: invert(change, base, [])

  defp invert([], _base, so_far), do: finalize(so_far, [])

  defp invert([head | rest], base, so_far) do
    count = Op.size(head)

    case head do
      %Insert{} ->
        invert(rest, base, push(so_far, %Delete{count: count}))

      %Retain{attrs: nil} when is_integer(head.target) ->
        invert(rest, seek(base, count), push(so_far, %Retain{target: count}))

      %Retain{} when is_integer(head.target) ->
        {chunk, rest_base} = split(base, count)
        invert(rest, rest_base, push_inverted(head, chunk, so_far))

      %Retain{} ->
        # this should crash if for some reason the count is not 1 (if in the future
        # custom embeds with size > 1 are supported and there is an instruction mismatch)
        {[base_op], rest_base} = split(base, count)
        base_embed = Content.from(base_op)

        inverted = %Retain{
          target: Content.invert(head.target, base_embed),
          attrs: Attrs.invert(head.attrs, base_op.attrs)
        }

        invert(rest, rest_base, [inverted | so_far])

      %Delete{} ->
        {chunk, rest_base} = split(base, count)
        invert(rest, rest_base, push_inverted(head, chunk, so_far))
    end
  end

  # op.attrs will always be a map
  defp push_inverted(%Retain{} = op, [head | rest], so_far) do
    case head do
      %Delete{} ->
        push_inverted(op, rest, [
          %Retain{target: Op.size(head), attrs: op.attrs} | so_far
        ])

      _ ->
        push_inverted(op, rest, [
          %Retain{target: Op.size(head), attrs: Attrs.invert(op.attrs, head.attrs)} | so_far
        ])
    end
  end

  defp push_inverted(%Delete{}, base_ops, so_far) do
    Enum.reverse(base_ops, so_far)
  end

  defp push_inverted(_, [], so_far), do: so_far

  @spec transform_index(non_neg_integer, t, priority) :: non_neg_integer
  @doc """
  Transforms a cursor/selection index against a delta.

  When a delta is applied to a document, cursor positions need to be adjusted.
  This function computes where an index should move to after the delta is applied.

  ## Parameters

  - `index` - The original cursor position
  - `delta` - The delta being applied
  - `priority` - Whether the cursor should be pushed by inserts at the same position

  ## Examples

      iex> Otzel.transform_index(5, [Otzel.insert("abc")], :right)
      8

      iex> Otzel.transform_index(5, [Otzel.retain(3), Otzel.delete(2)], :right)
      3

  """
  def transform_index(left, right, priority \\ :right)

  def transform_index(index, right, priority) when is_integer(index) do
    transform_index(0, index, right, priority)
  end

  defp transform_index(offset, index, _, _) when is_integer(index) and offset > index, do: index
  defp transform_index(_, index, [], _) when is_integer(index), do: index

  defp transform_index(offset, index, [%Delete{count: count} | delta], priority)
       when is_integer(index) do
    transform_index(offset, index - min(count, index - offset), delta, priority)
  end

  defp transform_index(offset, index, [op | delta], priority) when is_integer(index) do
    {offset, index} = Op.transform_index(offset, index, op, priority)
    transform_index(offset, index, delta, priority)
  end

  @spec transform(t, t, priority) :: t
  @doc """
  Transforms a delta against another concurrent delta.

  When two users make edits concurrently, their deltas need to be transformed
  against each other to maintain consistency. Given deltas A and B that were
  created from the same base document:

  - `transform(A, B, :right)` returns B' that can be applied after A
  - `transform(B, A, :left)` returns A' that can be applied after B

  The result satisfies: `compose(A, B') == compose(B, A')`

  ## Parameters

  - `from` - The delta that was applied first
  - `into` - The delta to transform
  - `priority` - Which delta wins when both insert at the same position

  ## Examples

      iex> a = [Otzel.insert("A")]
      iex> b = [Otzel.insert("B")]
      iex> Otzel.json(Otzel.transform(a, b, :right))
      [%{"insert" => "B"}]

  ## Priority

  The priority parameter determines what happens when both deltas insert at
  the same position:

  - `:right` - The `into` delta's insert comes after
  - `:left` - The `into` delta's insert comes before

  """
  def transform(left, right, priority \\ :right), do: transform(left, right, priority, [])

  defp transform([], [], _, so_far), do: finalize(so_far, [])

  defp transform([], [op | delta], priority, so_far) do
    transform([%Retain{target: Op.size(op)}], [op | delta], priority, so_far)
  end

  defp transform([op | delta], [], priority, so_far) do
    transform([op | delta], [%Retain{target: Op.size(op)}], priority, so_far)
  end

  defp transform([%Insert{} = head | from_rest], [%op{} | _] = into, priority, so_far)
       when op in [Retain, Delete] do
    transform(
      from_rest,
      into,
      priority,
      push(so_far, %Retain{target: Op.size(head)})
    )
  end

  defp transform([%Insert{} = head | from_rest], into, :left, so_far) do
    transform(
      from_rest,
      into,
      :left,
      push(so_far, %Retain{target: Op.size(head)})
    )
  end

  defp transform(from, [%Insert{} = head | into_rest], priority, so_far) do
    transform(
      from,
      into_rest,
      priority,
      push(so_far, head)
    )
  end

  defp transform([from_head | from_rest], [into_head | into_rest], priority, so_far) do
    {new_op, new_from, new_into} = Op.transform(from_head, into_head, priority)

    from_rest
    |> push(new_from)
    |> transform(push(into_rest, new_into), priority, push(so_far, new_op))
  end

  @spec compact(t) :: t
  @doc ~S"""
  Compacts Delta to satisfy [compactness](https://quilljs.com/guides/designing-the-delta-format/#compact) requirement.

  ```elixir
  iex> delta = [Otzel.insert("Hel"), Otzel.insert("lo"), Otzel.insert("World", %{"bold" => true})]
  iex> Otzel.json(Otzel.compact(delta))
  [%{"insert" => "Hello"}, %{"insert" => "World", "attributes" => %{"bold" => true}}]
  ```
  """
  def compact(ops) do
    case Enum.reverse(ops) do
      [%Retain{target: t, attrs: nil} | rest] when is_integer(t) ->
        backcompact(rest, [])

      other ->
        backcompact(other, [])
    end
  end

  defp backcompact([head | rest], [last | rest_so_far] = so_far) do
    case Op.merge_into(last, head) do
      nil ->
        backcompact(rest, [head | so_far])

      merged ->
        backcompact(rest, [merged | rest_so_far])
    end
  end

  defp backcompact([], so_far), do: so_far
  defp backcompact([head | rest], []), do: backcompact(rest, [head])

  @doc """
  Performs semantic cleanup on a diff, simplifying interleaved delete/insert
  sequences into cleaner delete-then-insert patterns when the common text
  is minimal.

  This makes diffs more human-readable by avoiding overly granular changes.

  The optional `dst_content` parameter provides the destination content,
  which is needed to extract retained content when converting retains to inserts.
  The optional `dst_attrs_index` parameter provides the destination attributes index,
  which maps positions to their attributes for proper attr handling.
  """
  @spec cleanup_semantic(t, Otzel.Content.t() | nil, list() | nil) :: t
  def cleanup_semantic(ops, dst_content \\ nil, dst_attrs_index \\ nil) do
    ops
    |> group_edit_sequences([])
    |> Enum.flat_map(&simplify_edit_group(&1, dst_content, dst_attrs_index))
    |> compact()
  end

  # Groups operations into sequences of edits (delete/insert/small-retain) and non-edits (large retain)
  # Small retains (target <= 4 chars with attrs that change) are included in edit groups
  defp group_edit_sequences([], acc), do: Enum.reverse(acc)

  defp group_edit_sequences(ops, acc) do
    {edit_group, rest} = take_edit_group(ops, [])

    case {edit_group, rest} do
      {[], [%Retain{} = retain | rest2]} ->
        # Large retain that doesn't belong in an edit group
        group_edit_sequences(rest2, [{:retain, retain} | acc])

      {[], []} ->
        Enum.reverse(acc)

      {edits, rest2} ->
        group_edit_sequences(rest2, [{:edit, edits} | acc])
    end
  end

  # Take consecutive operations that form an edit group
  # Small retains (<=4 chars) are included if they're surrounded by edits
  defp take_edit_group([], acc), do: {Enum.reverse(acc), []}

  defp take_edit_group([%Retain{target: t, attrs: attrs} = retain | rest], acc)
       when is_integer(t) do
    # Include small retains in edit groups, or retains that change attributes
    if t <= 4 or attrs != nil do
      take_edit_group(rest, [retain | acc])
    else
      # Large retain with no attr changes - ends the edit group
      {Enum.reverse(acc), [retain | rest]}
    end
  end

  defp take_edit_group([%Retain{} = retain | rest], []) do
    # Non-integer retain at start - treat as standalone
    {[], [retain | rest]}
  end

  defp take_edit_group([%Retain{} = retain | rest], acc) do
    # Non-integer retain in middle of edit group - include it
    take_edit_group(rest, [retain | acc])
  end

  defp take_edit_group([op | rest], acc) do
    take_edit_group(rest, [op | acc])
  end

  # Simplify an edit group: if the common text ratio is low, convert to delete-all + insert-all
  defp simplify_edit_group({:retain, retain}, _dst_content, _dst_attrs_index), do: [retain]

  defp simplify_edit_group({:edit, ops}, dst_content, dst_attrs_index) do
    # Calculate total delete count, collect inserts, and track retain info
    {delete_count, inserts_and_retains, _dst_pos} =
      Enum.reduce(ops, {0, [], 0}, fn
        %Delete{count: c}, {del, items, dst_pos} ->
          {del + c, items, dst_pos}
        %Insert{content: c} = i, {del, items, dst_pos} ->
          {del, [{:insert, i} | items], dst_pos + Content.size(c)}
        %Retain{target: t, attrs: attrs}, {del, items, dst_pos} when is_integer(t) ->
          {del + t, [{:retain, t, attrs, dst_pos} | items], dst_pos + t}
        other, {del, items, dst_pos} ->
          {del, [{:other, other} | items], dst_pos + 1}
      end)

    items = Enum.reverse(inserts_and_retains)

    # Calculate the amount of "retained" content in the edit group
    retained_count =
      Enum.reduce(items, 0, fn
        {:retain, t, _, _}, acc -> acc + t
        _, acc -> acc
      end)

    # Calculate total insert size (including retained)
    insert_size =
      Enum.reduce(items, 0, fn
        {:insert, %Insert{content: c}}, acc -> acc + Content.size(c)
        {:retain, t, _, _}, acc -> acc + t
        _, acc -> acc
      end)

    # If retained content is less than 20% of the total edit size, simplify
    total_edit_size = delete_count + insert_size - retained_count
    threshold = div(total_edit_size, 5)  # 20%

    if retained_count <= threshold and delete_count > 0 and dst_content != nil do
      # Convert to: delete all, then insert all (converting retains to inserts)
      inserts = convert_retains_to_inserts(items, dst_content, dst_attrs_index)
      [%Delete{count: delete_count} | merge_inserts(inserts)]
    else
      # Keep the original ops, but merge adjacent same-type operations
      merge_adjacent_ops(ops)
    end
  end

  # Convert retain operations to insert operations using dst_content
  # Uses dst_attrs_index to look up actual destination attributes
  defp convert_retains_to_inserts(items, dst_content, dst_attrs_index) do
    Enum.map(items, fn
      {:insert, insert} -> insert
      {:retain, count, _diff_attrs, dst_pos} ->
        # Extract content from destination at this position
        {_, rest} = Content.take(dst_content, dst_pos)
        {content, _} = Content.take(rest, count)
        # Look up actual destination attrs instead of using diff attrs
        dst_attrs = lookup_attrs_at(dst_attrs_index, dst_pos)
        %Insert{content: content, attrs: dst_attrs}
      {:other, other} -> other
    end)
  end

  # Look up attributes at a given position in the attrs index
  defp lookup_attrs_at(nil, _pos), do: nil
  defp lookup_attrs_at([], _pos), do: nil
  defp lookup_attrs_at([{start, end_pos, attrs} | _rest], pos) when pos >= start and pos < end_pos, do: attrs
  defp lookup_attrs_at([_ | rest], pos), do: lookup_attrs_at(rest, pos)

  # Merge adjacent inserts with compatible attributes
  # Attrs are compatible if they have the same non-nil values (nil means "remove attr")
  defp merge_inserts([]), do: []
  defp merge_inserts([single]), do: [single]

  defp merge_inserts([%Insert{attrs: attrs1} = first | rest]) do
    {compatible, different} = Enum.split_while(rest, fn
      %Insert{attrs: attrs2} -> attrs_compatible?(attrs1, attrs2)
      _ -> false
    end)

    if compatible == [] do
      [first | merge_inserts(rest)]
    else
      # Merge attrs: keep non-nil values from all, preferring later ones
      merged_attrs =
        [first | compatible]
        |> Enum.map(& &1.attrs)
        |> Enum.reduce(&merge_attrs/2)

      merged_content =
        [first | compatible]
        |> Enum.map(& &1.content)
        |> Content.concatenate()

      [%Insert{content: merged_content, attrs: merged_attrs} | merge_inserts(different)]
    end
  end

  defp merge_inserts([other | rest]), do: [other | merge_inserts(rest)]

  # Check if two attr maps are compatible for merging
  # Compatible means: same non-nil values, and nil values only remove keys present in the other
  # E.g., %{"bold" => true} is compatible with %{"bold" => true, "color" => nil}
  # But %{"bold" => true} is NOT compatible with %{"italic" => true}
  defp attrs_compatible?(nil, nil), do: true
  defp attrs_compatible?(nil, attrs), do: all_values_nil?(attrs)
  defp attrs_compatible?(attrs, nil), do: all_values_nil?(attrs)

  defp attrs_compatible?(attrs1, attrs2) when is_map(attrs1) and is_map(attrs2) do
    # Get non-nil values from both
    non_nil1 = attrs1 |> Enum.reject(fn {_, v} -> v == nil end) |> Map.new()
    non_nil2 = attrs2 |> Enum.reject(fn {_, v} -> v == nil end) |> Map.new()

    # They're compatible if the non-nil parts are equal
    non_nil1 == non_nil2
  end

  defp all_values_nil?(nil), do: true
  defp all_values_nil?(attrs) when is_map(attrs) do
    Enum.all?(attrs, fn {_, v} -> v == nil end)
  end

  # Merge two attr maps, keeping non-nil values (later wins for conflicts)
  defp merge_attrs(nil, attrs), do: attrs
  defp merge_attrs(attrs, nil), do: attrs

  defp merge_attrs(attrs1, attrs2) when is_map(attrs1) and is_map(attrs2) do
    # Start with attrs1, overlay attrs2's non-nil values
    result =
      Map.merge(attrs1, attrs2, fn _key, v1, v2 ->
        # Prefer non-nil values; if both non-nil, prefer v2
        if v2 == nil, do: v1, else: v2
      end)

    # Remove nil values from result
    result
    |> Enum.reject(fn {_, v} -> v == nil end)
    |> Map.new()
    |> case do
      empty when map_size(empty) == 0 -> nil
      map -> map
    end
  end

  # Merge adjacent operations of the same type
  defp merge_adjacent_ops([]), do: []
  defp merge_adjacent_ops([single]), do: [single]

  defp merge_adjacent_ops([%Delete{count: c1}, %Delete{count: c2} | rest]) do
    merge_adjacent_ops([%Delete{count: c1 + c2} | rest])
  end

  defp merge_adjacent_ops([%Insert{attrs: attrs, content: c1}, %Insert{attrs: attrs, content: c2} | rest]) do
    merged = Content.merge_into(c1, c2)
    merge_adjacent_ops([%Insert{content: merged, attrs: attrs} | rest])
  end

  defp merge_adjacent_ops([first | rest]) do
    [first | merge_adjacent_ops(rest)]
  end

  @spec concat(t, t) :: t
  @doc """
  Concatenates two transformations into one

  ```elixir
  iex> Otzel.json(Otzel.concat([Otzel.insert("Hel")], [Otzel.insert("lo")]))
  [%{"insert" => "Hello"}]
  ```
  """
  def concat(left, right) do
    left
    |> Enum.reverse()
    |> Enum.reduce(right, &push(&2, &1))
  end

  @doc """
  Parses a delta from JSON format.

  Accepts a list of operation maps in the Quill Delta JSON format.

  ## Examples

      iex> json = [%{"insert" => "Hello"}, %{"insert" => " World", "attributes" => %{"bold" => true}}]
      iex> delta = Otzel.from_json(json)
      iex> length(delta)
      2

  """
  def from_json(json) when is_list(json) do
    Enum.map(json, &Op.from_json/1)
  end

  @string_module Application.compile_env(:otzel, :string_module, Otzel.Content.Iomemo)

  @spec insert(String.t() | Otzel.Content.t(), attrs :: nil | map) :: Otzel.Op.Insert.t()
  @doc """
  Creates an `Insert` operation with the given content and attributes.
  """
  def insert(content, attrs \\ nil)
  def insert(content, attrs) when is_map(attrs), do: insert(content, attrs, @string_module)
  def insert(content, nil), do: insert(content, nil, @string_module)
  def insert(content, module) when is_atom(module), do: insert(content, nil, module)

  def insert(content, attrs, module), do: Insert.new(content, attrs, module)

  @spec retain(non_neg_integer | Otzel.Content.t(), attrs :: nil | map) :: Otzel.Op.Retain.t()
  @doc """
  Creates a `Retain` operation with the given target and attributes.

  Note: if a the target is an embedded `t:Otzel.Content.t/0` then the "retain" operation
  signifies that the target should be treated as a delta for the embedded content.
  """
  def retain(target, attrs \\ nil), do: %Retain{target: target, attrs: attrs}

  @spec delete(non_neg_integer) :: Otzel.Op.Delete.t()
  @doc """
  Creates a `Delete` operation with the given count.
  """
  def delete(count), do: %Delete{count: count}

  @spec diff(t, t) :: t
  @doc """
  Computes the difference between two transformations, returning a new transformation that represents the changes needed to convert `src` into `dst`.
  Both `src` and `dst` should be strictly lists of `Insert` operations.

  Note that the following invariant holds for compact transformation `a`: `a == Otzel.compose(b, Otzel.diff(a, b))`

  ```elixir
  iex> Otzel.diff([Otzel.insert("Hello")], [Otzel.insert("Hello!")])
  [Otzel.retain(5), Otzel.insert("!")]
  ```
  """
  def diff([], []), do: []

  def diff([], dst) do
    # Empty source, just return the destination inserts as-is
    dst
  end

  def diff(src, []) do
    # Empty destination, delete all source content
    src_size = Enum.reduce(src, 0, fn %Insert{content: c}, acc -> acc + Content.size(c) end)
    if src_size > 0, do: [%Delete{count: src_size}], else: []
  end

  def diff(src, dst) do
    src_content = src |> to_content_list() |> Content.concatenate()
    dst_content = dst |> to_content_list() |> Content.concatenate()

    # Build indices of positions to their attributes
    src_attrs_index = build_attrs_index(src)
    dst_attrs_index = build_attrs_index(dst)

    # Get the raw diff operations
    diff_ops = Content.diff(src_content, dst_content)

    # When content is identical but attrs differ, generate retains for attr changes
    diff_ops =
      if diff_ops == [] and Content.size(src_content) > 0 do
        [%Retain{target: Content.size(src_content)}]
      else
        diff_ops
      end

    # Apply attributes from destination to Insert/Retain operations,
    # perform semantic cleanup, and compact to remove trailing retains
    diff_ops
    |> apply_dst_attrs(src_attrs_index, dst_attrs_index)
    |> cleanup_semantic(dst_content, dst_attrs_index)
  rescue
    _ in FunctionClauseError ->
      raise "diffs must only be performed on documents"
  end

  # Builds an index mapping character positions in the destination to their attributes.
  # Returns a list of {start_position, end_position, attrs} tuples.
  defp build_attrs_index(dst) do
    {index, _pos} =
      Enum.reduce(dst, {[], 0}, fn %Insert{content: content, attrs: attrs}, {acc, pos} ->
        size = Content.size(content)
        {[{pos, pos + size, attrs} | acc], pos + size}
      end)

    Enum.reverse(index)
  end

  # Applies destination attributes to Insert and Retain operations in the diff.
  # Tracks positions in both source and destination.
  # If an Insert/Retain spans multiple attr boundaries, it is split.
  defp apply_dst_attrs(ops, src_attrs_index, dst_attrs_index) do
    {result, _src_pos, _dst_pos} =
      Enum.reduce(ops, {[], 0, 0}, fn
        %Insert{content: content} = insert, {acc, src_pos, dst_pos} ->
          size = Content.size(content)
          # Split the insert at attribute boundaries (inserts only use dst attrs)
          split_inserts = split_insert_by_attrs(insert, dst_pos, dst_attrs_index)
          {Enum.reverse(split_inserts) ++ acc, src_pos, dst_pos + size}

        %Retain{target: target}, {acc, src_pos, dst_pos} when is_integer(target) ->
          # Split the retain at attribute boundaries, computing attr diffs
          split_retains = split_retain_by_attrs(target, src_pos, dst_pos, src_attrs_index, dst_attrs_index)
          {Enum.reverse(split_retains) ++ acc, src_pos + target, dst_pos + target}

        %Retain{} = retain, {acc, src_pos, dst_pos} ->
          # For non-integer retains (embedded content), compute attr diff
          src_attrs = get_attrs_at(src_attrs_index, src_pos)
          dst_attrs = get_attrs_at(dst_attrs_index, dst_pos)
          attr_diff = Attrs.diff(src_attrs, dst_attrs)
          updated_retain = %{retain | attrs: attr_diff}
          {[updated_retain | acc], src_pos + 1, dst_pos + 1}

        %Delete{count: count} = delete, {acc, src_pos, dst_pos} ->
          # Deletes advance source position but not destination
          {[delete | acc], src_pos + count, dst_pos}
      end)

    Enum.reverse(result)
  end

  # Splits an Insert operation at attribute boundaries from the destination.
  # Returns a list of Insert operations, each with the correct attrs.
  defp split_insert_by_attrs(%Insert{content: content} = insert, dst_pos, dst_attrs_index) do
    size = Content.size(content)
    end_pos = dst_pos + size

    # Find all attr boundaries within this insert's range
    splits = find_attr_splits(dst_attrs_index, dst_pos, end_pos)

    case splits do
      [{_start, _end, attrs}] ->
        # Single attr region, no split needed
        [%{insert | attrs: attrs}]

      _ ->
        # Multiple attr regions, need to split the content
        split_content_by_attrs(content, dst_pos, splits)
    end
  end

  # Gets attrs at a specific position from the index
  defp get_attrs_at(index, pos) do
    Enum.find_value(index, nil, fn {s, e, attrs} ->
      if pos >= s and pos < e, do: attrs
    end)
  end

  # Finds attr regions that overlap with the given range [start_pos, end_pos)
  defp find_attr_splits(index, start_pos, end_pos) do
    index
    |> Enum.filter(fn {s, e, _attrs} -> e > start_pos and s < end_pos end)
    |> Enum.map(fn {s, e, attrs} ->
      # Clamp to the insert's range
      {max(s, start_pos), min(e, end_pos), attrs}
    end)
  end

  # Splits content according to attr boundaries and creates Insert ops
  defp split_content_by_attrs(content, base_pos, splits) do
    Enum.map(splits, fn {start_pos, end_pos, attrs} ->
      offset = start_pos - base_pos
      length = end_pos - start_pos

      # Take the portion of content for this split
      {_, rest} = Content.take(content, offset)
      {portion, _} = Content.take(rest, length)

      %Insert{content: portion, attrs: attrs}
    end)
  end

  # Splits a Retain operation at attribute boundaries.
  # Computes the attr diff between source and destination for each region.
  # Returns a list of Retain operations, each with the correct attr diff.
  defp split_retain_by_attrs(count, src_pos, dst_pos, src_attrs_index, dst_attrs_index) do
    # For retains, we need to find all boundaries in BOTH src and dst
    # and compute the attr diff for each segment
    src_end = src_pos + count
    dst_end = dst_pos + count

    # Get boundaries from both indices
    src_splits = find_attr_splits(src_attrs_index, src_pos, src_end)
    dst_splits = find_attr_splits(dst_attrs_index, dst_pos, dst_end)

    # Merge the boundaries and compute attr diffs
    merge_attr_splits_for_retain(src_splits, dst_splits, src_pos, dst_pos)
  end

  # Merges source and destination attr splits and computes attr diffs for Retain ops
  defp merge_attr_splits_for_retain(src_splits, dst_splits, src_base, dst_base) do
    # Collect all boundary points (relative to the retain range)
    src_boundaries = Enum.flat_map(src_splits, fn {s, e, _} -> [s - src_base, e - src_base] end)
    dst_boundaries = Enum.flat_map(dst_splits, fn {s, e, _} -> [s - dst_base, e - dst_base] end)

    all_boundaries =
      (src_boundaries ++ dst_boundaries)
      |> Enum.uniq()
      |> Enum.sort()

    # Create segments between consecutive boundaries
    segments = Enum.chunk_every(all_boundaries, 2, 1, :discard)

    Enum.map(segments, fn [start_offset, end_offset] ->
      length = end_offset - start_offset
      src_attrs = find_attrs_at(src_splits, src_base + start_offset)
      dst_attrs = find_attrs_at(dst_splits, dst_base + start_offset)

      # Compute the attr diff: what changes are needed to go from src_attrs to dst_attrs
      attr_diff = Attrs.diff(src_attrs, dst_attrs)

      %Retain{target: length, attrs: attr_diff}
    end)
  end

  # Finds the attributes for a given absolute position in an attr index
  defp find_attrs_at(index, pos) do
    Enum.find_value(index, nil, fn {start_pos, end_pos, attrs} ->
      if pos >= start_pos and pos < end_pos, do: attrs
    end)
  end

  defp to_content_list(document) do
    Enum.map(document, fn %Insert{} = insert -> insert.content end)
  end

  @doc """
  Converts a delta to a JSON-compatible format.

  Returns a list of maps in the Quill Delta JSON format, suitable for
  serialization with `JSON.encode!/1` or transmission over the wire.

  ## Examples

      iex> delta = [Otzel.insert("Hello"), Otzel.insert(" World", %{"bold" => true})]
      iex> Otzel.json(delta)
      [%{"insert" => "Hello"}, %{"insert" => " World", "attributes" => %{"bold" => true}}]

  """
  def json(src) do
    src
    |> JSON.encode!()
    |> JSON.decode!()
  end

  # generically useful utilities

  # performs Enum.reverse on the list, but making sure that the last element is not an empty Retain instruction.
  defp finalize([%{__struct__: Retain, target: int, attrs: nil} | rest], [])
       when is_integer(int) do
    case rest do
      [] -> []
      [last | rest] -> finalize(rest, [last])
    end
  end

  defp finalize([head | rest], forward) do
    finalize(rest, push(forward, head))
  end

  defp finalize([], forward), do: forward

  def _codepoints(string), do: _codepoints(string, 0)

  defp _codepoints(<<_::utf8, rest::binary>>, count), do: _codepoints(rest, count + 1)
  defp _codepoints(<<>>, count), do: count
end

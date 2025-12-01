use Protoss

defprotocol Otzel.Op do
  @type t :: Otzel.Op.Insert.t() | Otzel.Op.Retain.t() | Otzel.Op.Delete.t()

  @spec merge_into(t, t) :: t | nil
  def merge_into(op1, op2)

  @spec size(t) :: non_neg_integer
  def size(operation)

  @spec take(t, non_neg_integer) :: {t, t | nil}
  def take(operation, count)
after
  alias Otzel.Attrs
  alias Otzel.Content
  alias Otzel.Op.Insert
  alias Otzel.Op.Retain
  alias Otzel.Op.Delete

  def json_encoders do
    cond do
      Code.ensure_loaded?(JSON) ->
        [JSON.Encoder]

      Code.ensure_loaded?(Jason) ->
        [Jason.Encoder]

      :else ->
        :otzel
        |> Application.get_env(:json_encoders)
        |> List.wrap()
    end
  end

  # necessary to prevent the compiler from requiring the module (which causes a circular dependency)
  # since the compiler checks to correctness on the child fields of the struct.  We don't have
  # any in this case.
  defmacrop struct_of(module) do
    quote do
      %{__struct__: unquote(module)}
    end
  end

  @spec compose(t, t) :: {t | nil, t, t}
  def compose(a, b) do
    # TODO: collapse this!
    {{op1, rest1}, {op2, rest2}} = next(a, b)

    composed =
      case {op1, op2} do
        {struct_of(Retain), struct_of(Delete)} ->
          op2

        {struct_of(Retain), struct_of(Retain)} when is_integer(op1.target) ->
          %{op2 | attrs: Attrs.compose(op1.attrs, op2.attrs, true)}

        {struct_of(module), struct_of(Retain)}
        when module in [Insert, Retain] and is_integer(op2.target) ->
          %{op1 | attrs: Attrs.compose(op1.attrs, op2.attrs)}

        {struct_of(Insert), struct_of(Retain)} when not is_integer(op2.target) ->
          struct!(Insert,
            content: Content.compose(op1.content, op2.target),
            attrs: Attrs.compose(op1.attrs, op2.attrs)
          )

        {struct_of(Retain), struct_of(Retain)} ->
          struct!(Retain,
            target: Content.compose(op1.target, op2.target),
            attrs: Attrs.compose(op1.attrs, op2.attrs)
          )

        _ ->
          nil
      end

    {composed, rest1, rest2}
  end

  @spec next(t, t) :: {t, t, t, t}
  defp next(a, b) do
    size = min(size(a), size(b))
    {take(a, size), take(b, size)}
  end

  @spec transform_index(non_neg_integer, non_neg_integer, t, Otzel.priority()) :: non_neg_integer
  def transform_index(offset, index, op, priority) do
    count = size(op)

    case op do
      struct_of(Insert) when priority == :right ->
        {offset + count, index + count}

      struct_of(Insert) when offset < index ->
        {offset + count, index + count}

      _ ->
        {offset + count, index}
    end
  end

  @spec transform(a :: t, b :: t, Otzel.priority()) :: {t, t, t}
  def transform(a, b, priority) do
    case next(a, b) do
      {{struct_of(Delete), a_rest}, {_, b_rest}} ->
        {nil, a_rest, b_rest}

      {{_, a_rest}, {struct_of(Delete) = new_op, b_rest}} ->
        {new_op, a_rest, b_rest}

      # delegate to embed handler if both are retains with the same embed type
      {{from, a_rest}, {into, b_rest}} when from.target.__struct__ == into.target.__struct__ ->
        {struct!(Retain,
           target: Content.transform(from.target, into.target, priority),
           attrs: Attrs.transform(from.attrs, into.attrs, priority)
         ), a_rest, b_rest}

      {{from, a_rest}, {into, b_rest}} when is_integer(from.target) and is_map(into.target) ->
        {%{into | attrs: Attrs.transform(from.attrs, into.attrs, priority)}, a_rest, b_rest}

      {{from, a_rest}, {into, b_rest}} ->
        {struct!(Retain,
           target: size(from),
           attrs: Attrs.transform(from.attrs, into.attrs, priority)
         ), a_rest, b_rest}
    end
  end

  def from_json(%{"insert" => _} = json), do: Insert.from_json(json)

  def from_json(%{"retain" => _} = json), do: Retain.from_json(json)

  def from_json(%{"delete" => _} = json), do: Delete.from_json(json)
end

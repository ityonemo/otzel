use Protoss

defprotocol Otzel.Content do
  @spec invert(t, t) :: t
  def invert(content1, content2)

  @spec compose(t, t) :: t
  def compose(content1, content2)

  @spec transform(t, t, Otzel.priority()) :: {t | nil, t, t}
  def transform(content1, content2, priority)

  @spec merge_into(t, t) :: t | nil
  def merge_into(content1, content2)

  @spec take(t, non_neg_integer) :: {t, t | nil}
  def take(content, count)

  @spec size(t) :: non_neg_integer
  def size(content)

  @spec diff(t, t) :: [insert: t, equals: t, delete: t]
  def diff(src, dst)

  @spec as_binary(t) :: binary | nil
  def as_binary(content)
after
  alias Otzel.Op.Insert
  alias Otzel.Op.Retain
  alias Otzel.Attr

  defmacro __using__(opts) do
    if opts[:atomic] do
      quote do
        def size(_), do: 1
        def take(op, _count), do: {op, nil}
        def merge_into(_, _), do: nil
        def as_binary(_), do: nil
      end
    end
  end

  @callback diff(t, t, Attr.t(), Attr.t()) :: Otzel.t() | nil
  @optional_callbacks diff: 4

  def from(%Retain{} = op), do: op.target
  def from(%Insert{} = op), do: op.content

  def remap_inserts(ops, module), do: Enum.map(ops, &remap_insert(&1, module))

  defp remap_insert(%Insert{} = insert, String) do
    if binary = as_binary(insert.content) do
      %{insert | content: binary}
    else
      insert
    end
  end

  defp remap_insert(%Insert{} = insert, module) do
    if binary = as_binary(insert.content) do
      %{insert | content: module.new(binary)}
    else
      insert
    end
  end

  defp remap_insert(op, _module), do: op

  def concatenate(list = [%module{} | _]), do: module.concatenate(list)
  def concatenate(list = [head | _]) when is_binary(head), do: IO.iodata_to_binary(list)
end

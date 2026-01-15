defmodule Otzel.Op.Insert do
  @moduledoc """
  An operation that inserts new content at the current position.

  Insert operations are the building blocks of documents in the delta format.
  A document is represented as a list of insert operations.

  ## Fields

  - `:content` - The content to insert (string or embedded content)
  - `:attrs` - Optional map of formatting attributes

  ## Examples

      # Plain text insert
      %Otzel.Op.Insert{content: "Hello", attrs: nil}

      # Insert with formatting
      %Otzel.Op.Insert{content: "Bold", attrs: %{"bold" => true}}

      # Using helper function
      Otzel.insert("Hello")
      Otzel.insert("Bold", %{"bold" => true})

  """

  use Otzel.Op

  @enforce_keys [:content]
  defstruct @enforce_keys ++ [:attrs]

  alias Otzel.Attrs
  alias Otzel.Content
  alias Otzel.Op
  alias Otzel.Op.Retain
  alias Otzel.Op.Delete
  alias Otzel.Op.Insert

  # Use codepoints instead of graphemes for consistent counting
  defp codepoint_length(string), do: length(String.codepoints(string))

  @type t :: %__MODULE__{
          content: Otzel.Content.t(),
          attrs: Attrs.t()
        }

  def new(content, attrs, _) when is_struct(content),
    do: %__MODULE__{content: content, attrs: attrs}

  def new(content, attrs, string_module) do
    content =
      case string_module do
        String ->
          IO.iodata_to_binary(content)

        _ ->
          string_module.new(content)
      end

    %__MODULE__{content: content, attrs: attrs}
  end

  defguard matching(c1, c2)
           when (is_map(c1) and is_map(c2) and c1.__struct__ == c2.__struct__) or
                  (is_binary(c1) and is_binary(c2))

  def merge_into(%{content: c1, attrs: attrs}, %__MODULE__{content: c2, attrs: attrs})
      when matching(c1, c2) do
    case Content.merge_into(c1, c2) do
      nil -> nil
      merged -> %__MODULE__{content: merged, attrs: attrs}
    end
  end

  def merge_into(_, _), do: nil

  def size(insert), do: Content.size(insert.content)

  def take(insert, count) do
    case Content.take(insert.content, count) do
      {taken, nil} ->
        {%{insert | content: taken}, nil}

      {taken, rest} ->
        {%{insert | content: taken}, %{insert | content: rest}}
    end
  end

  # note: in all cases `diff` should be passed content with the same size

  def diff(%{content: same} = left, %{content: same} = right) do
    [%Retain{target: Op.size(same), attrs: Attrs.diff(left.attrs, right.attrs)}]
  end

  def diff(left, right) when is_binary(left.content) and is_binary(right.content) do
    attrs = Attrs.diff(left.attrs, right.attrs)

    left.content
    |> String.myers_difference(right.content)
    |> Enum.map(fn
      {:eq, same} ->
        %Retain{target: codepoint_length(same), attrs: attrs}

      {:del, deleted} ->
        %Delete{count: codepoint_length(deleted)}

      {:ins, inserted} ->
        %Insert{content: inserted, attrs: attrs}
    end)
  end

  @embed_encoder Application.compile_env(:otzel, :embed_encoder)

  def from_json(%{"insert" => content} = json, opts) do
    embedded = if encoder = Keyword.get(opts, :embed_encoder, @embed_encoder) do
      {mod, fun} = encoder
      apply(mod, fun, [content])
    else
      content
    end
    %__MODULE__{content: embedded, attrs: Map.get(json, "attributes")}
  end
end

require Otzel.Op

for json_encoder <- Otzel.Op.json_encoders() do
  defimpl json_encoder, for: Otzel.Op.Insert do
    def encode(%{content: content, attrs: nil}, opts) do
      unquote(json_encoder).encode(%{"insert" => content}, opts)
    end

    def encode(%{content: content, attrs: attrs}, opts) do
      unquote(json_encoder).encode(%{"insert" => content, "attributes" => attrs}, opts)
    end
  end
end

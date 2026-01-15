unless Application.compile_env(:otzel, :no_ecto) do
  unless Code.ensure_loaded?(Ecto.Type) do
    raise CompileError,
      description: """
      Ecto is required but not available.

      Add {:ecto, "~> 3.0"} to your deps, or set:

          config :otzel, :no_ecto, true

      to disable Ecto integration.
      """
  end

  defmodule Otzel.Ecto.Delta do
    @moduledoc """
    An Ecto type for storing Otzel deltas as JSON/JSONB.

    This type allows you to store OT deltas directly in your database,
    automatically handling serialization to JSON for storage and
    deserialization back to Otzel operation structs on load.

    ## Usage

        defmodule MyApp.Document do
          use Ecto.Schema

          schema "documents" do
            field :content, Otzel.Ecto.Delta
            timestamps()
          end
        end

    ## Database Column

    Use a `:map` type in your migration, which becomes `jsonb` in PostgreSQL:

        create table(:documents) do
          add :content, :map
          timestamps()
        end

    ## Storage Format

    Deltas are stored in the standard Quill Delta JSON format:

        [
          {"insert": "Hello "},
          {"insert": "World", "attributes": {"bold": true}}
        ]

    """

    use Ecto.Type

    @impl true
    def type, do: :map

    @impl true
    def cast(delta) when is_list(delta), do: {:ok, delta}

    def cast(json) when is_binary(json) do
      case JSON.decode(json) do
        {:ok, data} when is_list(data) -> {:ok, Otzel.from_json(data)}
        _ -> :error
      end
    end

    def cast(_), do: :error

    @impl true
    def load(data) when is_list(data), do: {:ok, Otzel.from_json(data)}
    def load(_), do: :error

    @impl true
    def dump(delta) when is_list(delta), do: {:ok, delta}
    def dump(_), do: :error

    @impl true
    def equal?(a, b), do: a == b
  end
end

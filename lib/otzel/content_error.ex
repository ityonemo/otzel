defmodule Otzel.ContentError do
  @moduledoc """
  Raised when there is a type mismatch between content types in OT operations.

  This error occurs when attempting operations that require compatible content types,
  such as inverting an embedded retain against a string base, or composing incompatible
  content types.

  ## Fields

  - `:message` - Human-readable description of the error
  - `:operation` - The operation being performed (e.g., `:invert`, `:compose`)
  - `:expected` - The expected content type or description
  - `:got` - The actual content type or value received
  """

  defexception [:message, :operation, :expected, :got]

  @impl true
  def message(%{message: message}) when is_binary(message), do: message

  def message(%{operation: op, expected: expected, got: got}) do
    "content type mismatch in #{op}: expected #{inspect(expected)}, got #{inspect(got)}"
  end
end

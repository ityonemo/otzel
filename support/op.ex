defmodule OtzelTest.Op do
  alias Otzel.Content.Ot

  def embed(ops), do: %Ot{transform: List.wrap(ops)}

  import Kernel, except: [=~: 2]

  def left =~ right do
    JSON.encode!(left) == JSON.encode!(right)
  end
end

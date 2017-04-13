defmodule Belt.FileInfo do
  @moduledoc """
  Struct for representing stored files.
  """

  @type t :: %__MODULE__{}

  defstruct(
    identifier: nil,
    config: nil,
    size: nil,
    hashes: [],
    modified: nil,
    url: :unavailable,
  )
end

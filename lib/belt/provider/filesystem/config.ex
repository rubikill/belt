defmodule Belt.Provider.Filesystem.Config do
  @moduledoc false
  defstruct(
    directory: nil,
    base_url: :unavailable,
    provider: Belt.Provider.Filesystem
  )
end

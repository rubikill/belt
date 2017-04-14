defmodule Belt.Config do
  def providers() do
    case Application.fetch_env(:belt, :providers) do
      :error ->
        filesystem = [Belt.Provider.Filesystem]
        sftp = if Code.ensure_loaded?(:ssh_sftp), do: [Belt.Provider.SFTP], else: []
        s3 = if Code.ensure_loaded?(ExAws), do: [Belt.Provider.S3], else: []
        filesystem ++ sftp ++ s3
      {:ok, val} -> val
    end
  end

  def timeout(),
    do: Application.get_env(:belt, :timeout, 10_000)

  def max_concurrency(),
    do: Application.get_env(:belt, :max_concurrency, 20)

  def stream_size(),
    do: Application.get_env(:belt, :stream_size, 1_048_576)

  def max_renames(),
    do: Application.get_env(:belt, :max_renames, 10)
end

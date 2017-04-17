defmodule Belt.Config do
  @moduledoc """
  Module for retrieving configuration and defaults.

  ## Usage
  ```
  # in config.exs
  config :belt,
    max_concurrency: 10,
    max_renames: 10

  config :belt, Belt.Provider.S3,
    max_concurrency: 5
  ```

  ```
  # in the application
  Belt.Config.get(Belt.Provider.S3, :max_concurrency)
  #=> 5
  Belt.Config.get(Belt.Provider.S3, :max_renames)
  #=> 10
  ```
  """

  @doc """
  Returns configuration value for `key`. If no value has been set in the
  configuration of the application, a default value is used instead.

  Raises an exception if no default value could be found.
  """
  @spec get(atom) :: term
  def get(key) do
    case Application.fetch_env(:belt, key) do
      {:ok, val} -> val
      :error -> get_default(key)
    end
  end

  @doc """
  Returns configuration value for `key` specific to `module`.
  If no value has been set in the configuration of the application, module,
  the application-wide default value is used instead.

  Raises an exception if no default value could be found.
  """
  @spec get(atom, atom) :: term
  def get(module, key) do
    with {:ok, module_config} <- Application.fetch_env(:belt, module),
         {:ok, val} <- Keyword.fetch(module_config, key) do
         val
    else
      :error -> get(key)
    end
  end

  defp get_default(:max_concurrency), do: 20

  defp get_default(:max_renames), do: 10

  defp get_default(:providers) do
    filesystem = [Belt.Provider.Filesystem]
    sftp = if Code.ensure_loaded?(:ssh_sftp), do: [Belt.Provider.SFTP], else: []
    s3 = if Code.ensure_loaded?(ExAws), do: [Belt.Provider.S3], else: []
    filesystem ++ sftp ++ s3
  end

  defp get_default(:stream_size), do: 1_048_576

  defp get_default(:timeout), do: 10_000

  defp get_default(key),
    do: raise("No configuration default found for #{inspect key}")
end

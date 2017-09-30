defmodule Belt.Provider do
  @moduledoc """
  Defines a Belt Provider.

  Providers allow Belt to interface with storage destinations.

  This module’s `__using__` macro automatically sets up supervision and
  GenStage handling for a provider. Alternatively, a provider may just adopt
  the Behaviour defined by `Belt.Provider` and provide a custom implementation
  of these components.

  ## Usage
  ```
  defmodule Belt.Provider.MyProvider do
    use Belt.Provider

    def new(options) do
      #…
    end
    #…
  end
  """

    @typedoc """
  Possible file sources for `Belt.Provider.store/3`. Currently supported types:
  - `Path.t` - a path to a file on the local filesystem
  - `%{path: Path.t, filename: String.t}` - a Map following the format of `Plug.Upload`
  """
  @type file_source :: Path.t | %{path: Path.t, filename: String.t}


  @typedoc """
  Configuration type used by provider callbacks.
  Contains provider-specific configuration data.
  """
  @type configuration :: %{required(:provider) => :atom}


  @typedoc """
  Identifier that can be used together with a configuration to retrieve or manipulate
  a stored file.
  """
  @type file_identifier :: String.t | %{identifier: String.t}




  @typedoc """
  Options supported by all providers for `Belt.store/3` and `Belt.store_async/3`.
  Additional options might be supported by certain providers and are documented
  there.
  """
  @type store_option ::
    {:hashes, [:crypto.hash_algorithms]} |
    {:key, String.t | :auto} |
    {:overwrite, boolean | :rename} |
    {:scope, String.t} |
    Belt.request_option |
    {:atom, term}


  @typedoc """
  Options supported by aĺl providers for `Belt.get_info/3`.
  Additional options might be supported by certain providers and are documented
  there.
  """
  @type info_option ::
    {:hashes, [:crypto.hash_algorithms]} |
    Belt.request_option |
    {atom | term}


  @typedoc """
  Options supported by aĺl providers for `Belt.get_url/3`.
  Additional options might be supported by certain providers and are documented
  there.
  """
  @type url_option ::
    Belt.request_option |
    {atom | term}


  @typedoc """
  Options supported by aĺl providers for `Belt.list_files/2`.
  Additional options might be supported by certain providers and are documented
  there.
  """
  @type list_files_option ::
    Belt.request_option |
    {atom | term}


  @typedoc """
  Options supported by aĺl providers for `Belt.delete/3`.
  Additional options might be supported by certain providers and are documented
  there.
  """
  @type delete_option ::
    Belt.request_option |
    {atom | term}


  @doc """
  Creates a new configuration struct.
  """
  @callback new(options :: list) ::
    {:ok, configuration} |
    {:error, term}


  @doc """
  Creates a new configuration struct with default credentials.
  Providers can implement this to pull defaults from the application
  configuration and/or environment variables at runtime.

  Additionally provided options will override the defaults.
  """
  @callback default(options :: list) ::
    {:ok, configuration} |
    {:error, term}


  @doc """
  Stores a file using the provided configuration.
  """
  @callback store(configuration, file_source :: file_source, [store_option]) ::
    {:ok, Belt.FileInfo.t} |
    {:error, term}

  @doc """
  Deletes a file using the provided configuration and identifier.
  """
  @callback delete(configuration, identifier, list) ::
    :ok |
    {:error, term}

  @doc """
  Deletes all file accessible through a configuration.
  """
  @callback delete_all(configuration, list) ::
    :ok |
    {:error, term}

  @doc """
  Deletes all files within a scope of a configuration.
  """
  @callback delete_scope(configuration, String.t, list) ::
    :ok |
    {:error, term}

  @doc """
  Retrieves `%Belt.FileInfo{}` struct for given file.
  """
  @callback get_info(configuration, identifier, [info_option]) ::
    {:ok, Belt.FileInfo.t}


  @doc """
  Retrieves url for given file.
  """
  @callback get_url(configuration, identifier, [url_option]) ::
    {:ok, Belt.FileInfo.t} | :unavailable | {:error, term}

  @doc """
  Lists all files for a given provider.
  """
  @callback list_files(configuration, [list_files_option]) ::
    {:ok, [identifier]} | {:error, term}

  @doc """
  Tests if a connection can be established with the given provider.
  """
  @callback test_connection(configuration, [Belt.request_option]) ::
    :ok | {:error, term}


  defmacro __using__(_opts) do
    quote do
      @behaviour Belt.Provider
      use Belt.Provider.Supervisor

      @doc false
      def start_link(event) do
        Task.start_link(fn -> init(event) end)
      end

      @doc false
      def init(event) do
        with {:ok, :ok} <- try_message(event, :register_worker, [self()]),
             {:ok, payload} <- try_message(event, :get_payload),
             {fun, args} <- payload,
             reply <- apply(__MODULE__, fun, args) do
             try_message(event, :finish, [reply])
          else
            other -> other
        end
      end

      #Attempt a GenServer.call and catch exit if GenServer has been terminated
      defp try_message(job, message, args \\ []) do
        try do
          result = apply(Belt.Job, message, [job | args])
          {:ok, result}
        catch
          :exit, {:noproc, _}
            -> {:error, "Task has gone away"}
        end
      end
    end
  end
end

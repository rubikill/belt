defmodule Belt do
  use GenStage

  @timeout Belt.Config.timeout()
  @providers Belt.Config.providers()

  @moduledoc """
  Extensible OTP Application written in Elixir for storing files remotely or
  locally through a unified API.

  The following backends are currently included:
  - `Belt.Provider.Filesystem` for local storage
  - `Belt.Provider.SFTP` for storing on SFTP servers with private key and
    username/password authentication
  - `Belt.Provider.S3` supports services with S3-compatible APIs such as
    *Amazon S3*, *EMC Elastic Cloud Storage* or *Minio* though `ExAws`.

  ## Basic usage
  ```
  #Simple file upload
  config = Belt.Provider.SFTP.new(host: "example.com", directory: "/var/files",
                                  user: "…", password: "…")
  Belt.store(config, "/path/to/local/file.ext")
  #=> {:ok, %Belt.FileInfo{…}}


  #Asynchronous file upload
  config = Belt.Provider.S3.new(access_key_id: "…", secret_access_key: "…",
                                bucket: "belt-file-bucket")
  {:ok, job} = Belt.store_async(config, "/path/to/local/file.ext")
  #Do other things while Belt is uploading in the background
  Belt.await(job)
  #=> {:ok, %Belt.FileInfo{…}}
  ```
  """

  @typedoc """
  Options for all requests made through Belt.
  Additional options might be supported by certain providers and are documented
  there.
  """
  @type request_option ::
    {:timeout, integer}


  @doc """
  Stores data from `file_source` using `config` and waits for the upload to
  complete. `file_source` can either be a local path to a file or a struct
  following the structure of `%Plug.Upload{}`.

  Returns `{:ok, %Belt.FileInfo{}}` or `{:error, reason}`

  ## Options
  The following options are supported by all providers. Some providers might
  offer additional options.

  - `:hashes` - `[:crypto.hash_algorithms]` - Hashes to include in the returned
    `Belt.FileInfo` struct.
  - `:key` - `String.t | :auto` - The key to be used for storing the file. For most
    providers, this corresponds to the file name. When set to `:auto`, Belt tries to
    derive a key name from `file_source`. Defaults to `:auto`
  - `:overwrite` - `true | false | :rename` - How to handle conflicting keys.
    Defaults to `:rename`.
  - `:scope` - `String.t` - A namespace to be used for storing the file.
    For most providers, this corresponds to the name of a subdirectory.
  - `:timeout` - `integer` - Timeout (in milliseconds) for the request
  """

  @spec store(Belt.Provider.configuration, Belt.Provider.file_source, [Belt.Provider.store_option]) ::
        {:ok, Belt.FileInfo.t} |
        {:error, term}
  def store(config, file_source, options \\ [])

  def store(config, %{filename: key, path: path}, options) do
    options = options
      |> Keyword.put_new(:key, key)
    store(config, path, options)
  end

  def store(config, path, options) when is_binary(path) do
    {:ok, job} = store_async(config, path, options)
    await(job, options)
  end


  @doc """
  Asynchronously stores data from `file_source` using `config`.

  `file_source` can either be a local path to a file or a struct
  following the structure of `%Plug.Upload{}`.

  Returns `{:ok, Belt.Job.t}`

  For available options see `Belt.store/3`.
  """
  @spec store_async(Belt.Provider.configuration, Belt.Provider.file_source, list) ::
        {:ok, Belt.Job.t}

  def store_async(config, file_source, options \\ [])

  def store_async(config, %{filename: key, path: path}, options) do
    options = options
      |> Keyword.put_new(:key, key)
    store_async(config, path, options)
  end

  def store_async(config, path, options) do
    options = Keyword.put_new(options, :key, Path.basename(path))
    path = Path.expand(path)
    GenServer.call(__MODULE__, {:store, [config, path, options]})
  end


  @doc """
  Retrieves information about a file in a `Belt.FileInfo` struct.

  ## Example
  ```
  Belt.get_info(config, identifier, hashes: [:sha256])
  #=> {:ok, %Belt.FileInfo{hashes: ["2c2…7ae"], …}}
  ```

  ## Options
  The following options are supported by all providers. Some providers might
  offer additional options.

  - `:hashes` - Include a list with hashes of the given algorithms in the result
  - `:timeout` - Timeout for this call in milliseconds
  """
  @spec get_info(Belt.Provider.configuration, Belt.Provider.file_identifier, [Belt.Provider.info_option]) ::
        {:ok, Belt.FileInfo.t} | {:error, term}
  def get_info(config, identifier, options \\ [])

  def get_info(config, %{identifier: identifier}, options),
    do: get_info(config, identifier, options)

  def get_info(config, identifier, options) do
    {:ok, job} = GenServer.call(__MODULE__, {:get_info, [config, identifier, options]})
    await(job, options)
  end


  @doc """
  Retrieves the public URL of a file (if available) identified by its identifier and configuration.
  Additional options might be supported by specific providers.

  Returns `{:ok, url}`, `:unavailable` or `{:error, term}`.

  ## Options
  The following options are supported by all providers. Some providers might
  offer additional options.

  - `:timeout` - Timeout for this call in milliseconds
  """
  @spec get_url(Belt.Provider.configuration, Belt.Provider.file_identifier, [Belt.Provider.url_option]) ::
        {:ok, String.t} |
        :unavailable |
        {:error, term}
  def get_url(config, identifier, options \\ [])

  def get_url(config, %{identifier: identifier}, options),
    do: get_url(config, identifier, options)

  def get_url(config, identifier, options) do
    {:ok, job} = GenServer.call(__MODULE__, {:get_url, [config, identifier, options]})
    await(job, options)
  end


  @doc """
  Returns list of all available file identifiers for a given configuration.

  ## Options
  The following options are supported by all providers. Some providers might
  offer additional options.
  - `:timeout` - Timeout for this call in milliseconds
  """
  @spec list_files(Belt.Provider.configuration, [Belt.Provider.list_files_option]) ::
        {:ok, list(Belt.Provider.identifier)} | {:error, term}
  def list_files(config, options \\ []) do
    {:ok, job} =  GenServer.call(__MODULE__, {:list_files, [config, options]})
    await(job, options)
  end


  @doc """
  Deletes file identified by its configuration and identifier.

  ## Options
  The following options are supported by all providers. Some providers might
  offer additional options.
  - `:timeout` - Timeout for this call in milliseconds
  """
  @spec delete(Belt.Provider.configuration, Belt.Provider.identifier, [Belt.Provider.delete_option]) ::
        :ok | {:error, String.t}
  def delete(config, identifier, options \\ [])

  def delete(config, %{identifier: identifier}, options),
    do: delete(config, identifier, options)

  def delete(config, identifier, options) do
    {:ok, job} = GenServer.call(__MODULE__, {:delete, [config, identifier, options]})
    await(job, options)
  end


  @doc """
  Convenience function for awaiting the reply of a running `Belt.Job`.

  Terminates the Job after it has been completed or the timeout has expired.

  ## Options
  - `:timeout` - `integer` - Maximum time (in milliseconds) to wait for the
    job to finish
  """
  @spec await(Belt.Job.t, [{atom, term}]) ::
        {:ok, term} | {:error, :timeout} | {:error, term}
  def await(job, options) do
    timeout = Keyword.get(options, :timeout, @timeout)
    with {:ok, reply} <- Belt.Job.await_and_shutdown(job, timeout) do
      reply
    else
      {:error, reason} -> {:error, reason}
      :timeout -> {:error, :timeout}
    end
  end


  @doc false
  def start_link do
    GenStage.start_link(__MODULE__, :ok, name: __MODULE__)
  end


  @doc false
  def init(state) do
    dispatcher = {
      GenStage.PartitionDispatcher,
      partitions: @providers,
      hash: fn(job) ->
        event = Belt.Job.get_payload(job)
        provider = elem(event, 1) |> List.first() |> Map.get(:provider)
        unless provider in @providers,
          do: raise("provider #{inspect provider} not registered with Belt")
        {job, provider}
      end
    }
    {:producer, state, [dispatcher: dispatcher]}
  end


  @doc false
  def handle_call({type, params}, _from, state)
  when type in [:store, :delete, :delete, :get_info, :get_url, :list_files] do
    job_name = List.last(params)
      |> Keyword.get(:name, :auto)
    reply = {:ok, job} = Belt.Job.new({type, params}, job_name)

    {:reply, reply, [job], state}
  end

  @doc false
  def handle_demand(_demand, state) do
    {:noreply, [], state}
  end
end

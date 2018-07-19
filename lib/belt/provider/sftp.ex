if Code.ensure_loaded? :ssh_sftp do
  defmodule Belt.Provider.SFTP do
    use Belt.Provider

    alias :ssh, as: SSH
    alias :ssh_sftp, as: SFTP
    alias Belt.Provider.Helpers

    @max_renames Belt.Config.get(__MODULE__, :max_renames)
    @stream_size Belt.Config.get(__MODULE__, :stream_size)

    @typedoc """
    Public key or public key fingerprint.
    """
    @type host_key ::
      :public_key.public_key |
      String.t

    @typedoc """
    Private key or private key PEM string.
    """
    @type user_key ::
      :public_key.private_key |
      String.t

    @typedoc """
    Options for creating an SFTP provider.
    """
    @type sftp_option ::
      {:host, String.t} |
      {:port, integer} |
      {:user, String.t} |
      {:password, String.t} |
      {:user_key, user_key} |
      {:host_key, host_key} |
      {:verify_host_key, boolean} |
      {:directory, String.t} |
      {:base_url, String.t}

    @doc """
    Creates a new SFTP provider configuration.

    ## Options
    - `base_url` - `String.t`: Used for generating file URLs.
    - `directory` - `String.t`: Directory on the SFTP server. Defaults to
      "." which refers to the working directory set by the server.
    - `host` - `String.t`: Hostname of the SFTP server.
    - `host_key` - `Belt.Provider.SFTP.host_key`: Fingerprint of the SFTP server.
      Can be traditional colon-separated MD5 fingerprint string or an
      OpenSSL-formatted string such as `"SHA256:aZGX[…]JePQ"`.
    - `password` - `String.t`: Password for authentication.
      Needs to be combined with `user` option.
    - `port` - `integer`: Port of the SFTP server. Defaults to 22.
    - `verify_host_key` - `boolean`: Whether the host key should be verified.
      Defaults to `true`.
    - `user` - `String.t`: Username for authentication.
      Needs to be combined with `password` option.
    - `user_key` - `Belt.Provider.SFTP.user_key`: Private key for authentication.
      Can be a `:public_key.private_key` record or a PEM certificate string.
    """
    @spec new([sftp_option]) :: {:ok, Belt.Provider.configuration}
    def new(opts) do
      config = %Belt.Provider.SFTP.Config{}
        |> Map.to_list()
        |> Enum.map(fn {key, default} ->
          case key do
            :"__struct__" -> {key, default}
            _ -> {key, Keyword.get(opts, key, default)}
          end
        end)
        |> Enum.into(%{})
      {:ok, config}
    end

    @doc """
    Creates a new SFTP provider configuration with default credentials.

    Any provided `options` override the default settings which are retrieved from
    the application configuration.

    ## Example
    ```
    # config.exs
    config :belt, Belt.Provider.SFTP,
    default: [
      host: "example.org",
      user: "foo",
      password: "bar"]
    ```
    """
    @spec default([sftp_option]) ::
      {:ok, Belt.Provider.configuration} |
      {:error, term}
    def default(options \\ []) do
      with {:ok, app_conf} <- Application.fetch_env(:belt, Belt.Provider.SFTP),
          {:ok, defaults} <- Keyword.fetch(app_conf, :default) do
          defaults
          |> Keyword.merge(options)
          |> __MODULE__.new()
      else
        _ -> {:error, :not_set}
      end
    end


    @doc """
    Implementation of the Provider.store/3 callback.
    """
    def store(config, file_source, options) do
      with {:ok, channel, connection_ref} <- connect(config, options),
          options = options |> Keyword.put(:channel, channel),
          options = options |> Keyword.put(:connection_ref, connection_ref),
          {:ok, identifier} <- do_store(config, file_source, options),
          {requested_hashes, options} <- Keyword.pop(options, :hashes, []),
          {:ok, info} <- do_get_info(config, identifier, options) do
          disconnect(channel, connection_ref)
          hashes = Belt.Hasher.hash_file(file_source, requested_hashes)
          {:ok, info |> Map.put(:hashes, hashes)}
      else
        {:error, reason} -> {:error, reason}
        other -> {:error, other}
      end
    end


    @doc """
    Implementation of the Provider.store_data/3 callback.
    """
    def store_data(config, iodata, options) do
      with {:ok, channel, connection_ref} <- connect(config, options),
          options = options |> Keyword.put(:channel, channel),
          options = options |> Keyword.put(:connection_ref, connection_ref),
          {:ok, identifier} <- do_store_data(config, iodata, options),
          {requested_hashes, options} <- Keyword.pop(options, :hashes, []),
          {:ok, info} <- do_get_info(config, identifier, options) do
          disconnect(channel, connection_ref)
          hashes = Belt.Hasher.hash(iodata, requested_hashes)
          {:ok, info |> Map.put(:hashes, hashes)}
      else
        {:error, reason} -> {:error, reason}
        other -> {:error, other}
      end
    end



    @doc """
    Implementation of the Provider.delete/3 callback.
    """
    def delete(config, identifier, options) do
      path = Path.join(config.directory, identifier)
      with {:ok, channel, connection_ref} <- connect(config, options),
          {:ok, path} <- Helpers.ensure_included(path, config.directory) do
          result = delete_scopes_and_files(channel, [], [path])
          disconnect(channel, connection_ref)
          result
      else
        {:error, reason} -> {:error, reason}
        other -> {:error, other}
      end
    end


    @doc """
    Implementation of the Provider.delete_all/2 callback.
    """
    def delete_all(config, options) do
      with {:ok, channel, connection_ref} <- connect(config, options) do
        {scopes, files} = traverse(channel, config.directory)
        result = delete_scopes_and_files(channel, scopes, files)
        disconnect(channel, connection_ref)
        result
      end
    end



    @doc """
    Implementation of the Provider.delete_scope/3 callback.
    """
    def delete_scope(config, scope, options) do
      with {:ok, channel, connection_ref} <- connect(config, options) do
        reply = delete_scopes_and_files_scope(config, channel, scope)
        disconnect(channel, connection_ref)
        reply
      end
    end

    defp delete_scopes_and_files_scope(config, channel, scope) do
      path = Path.join(config.directory, scope)
      with {:ok, path} <- Helpers.ensure_included(path, config.directory) do
        {scopes, files} = traverse(channel, path)
        delete_scopes_and_files(channel, scopes, files)
        :ssh_sftp.del_dir(channel, path)
        :ok
      else
        {:error, _} -> {:error, :invalid_scope}
      end
    end


    @doc """
    Implementation of the Provider.get_info/3 callback.
    """
    def get_info(config, identifier, options) do
      with {:ok, channel, connection_ref} <- connect(config, options),
          options = options |> Keyword.put(:channel, channel),
          options = options |> Keyword.put(:connection_ref, connection_ref) do
          info = do_get_info(config, identifier, options)
          disconnect(channel, connection_ref)
          info
      end
    end


    @doc """
    Implementation of the `Belt.Provider.get_url/3` callback.
    """
    def get_url(%{base_url: base_url}, identifier, _options) when is_binary(base_url) do
      url = base_url
        |> URI.merge(identifier)
        |> URI.to_string()
      {:ok, url}
    end

    def get_url(_, _, _), do: :unavailable


    @doc """
    Implementation of the `Belt.Provider.list_files/2` callback.
    """
    def list_files(config, options) do
      with {:ok, channel, connection_ref} <- connect(config, options) do
        files = traverse(channel, config.directory)
          |> elem(1)
          |> Enum.map(&Path.relative_to(&1, config.directory))
        disconnect(channel, connection_ref)
        {:ok, files}
      end
    end


    @doc """
    Implementation of the Provider.test_connection/2 callback.
    """
    def test_connection(config, options) do
      with {:ok, channel, connection_ref} <- connect(config, options) do
        disconnect(channel, connection_ref)
        :ok
      end
    end


    defp traverse(channel, directory),
      do: do_traverse(channel, [directory], [], [])

    defp do_traverse(channel, dirs, scopes, files)
    defp do_traverse(_channel, [], scopes, files), do: {scopes, files}

    defp do_traverse(channel, [dir | t], scopes, files) do
      with {:ok, dir_files} <- :ssh_sftp.list_dir(channel, dir  |> to_charlist()) do
        {new_dirs, new_files} = dir_files
          |> Enum.filter(fn(name) ->
            case name do
              name when name in ['.', '..', ".", "..",] -> false
              _ -> true
            end
          end)
          |> Enum.map(fn(name) ->
            path = Path.join(dir, name)
            {:ok, stat} = :ssh_sftp.read_file_info(channel, path |> to_charlist())
            stat = File.Stat.from_record(stat)
            {stat.type, path}
          end)
          |> Enum.reduce({[], []}, fn({type, path}, {dirs, files}) ->
            case type do
              :directory  -> {[path | dirs], files}
              :regular    -> {dirs, [path | files]}
              _           -> {dirs, files}
            end
          end)
        do_traverse(channel, new_dirs ++ t, new_dirs ++ scopes, new_files ++ files)
      end
    end


    defp connect(config, _options) do
      SSH.start()
      user = if config.user,
        do: config.user |> to_charlist(),
        else: ''
      password = if config.password,
        do: config.password |> to_charlist(),
      else: ''
      cb_private = [
        user_key: config.user_key,
        host_key: config.host_key,
        verify_host_key: config.verify_host_key
      ]
      ssh_opts = [
        user: user,
        password: password,
        key_cb: {Belt.Provider.SFTP.ClientKeyBehaviour, cb_private},
        user_interaction: false,
        silently_accept_hosts: true
      ]
      host = config.host |> String.to_charlist()
      port = config.port
      SFTP.start_channel(host, port, ssh_opts)
    end

    defp disconnect(channel, connection_ref) do
      :ok = :ssh_sftp.stop_channel(channel)
      :ok = :ssh.close(connection_ref)
    end

    defp delete_scopes_and_files(channel, scopes, files) do
      Enum.map(files, fn(file) ->
        :ssh_sftp.delete(channel, file |> to_charlist())
      end)
      Enum.map(scopes, fn(scope) ->
        :ssh_sftp.del_dir(channel, scope |> to_charlist())
      end)
      :ok
    end

    defp mkdir_p!(channel, name) do
      [base | segments] = Path.split(name)
      do_mkdir_p!(channel, base, segments)
    end

    defp do_mkdir_p!(_channel, base, []), do: base
    defp do_mkdir_p!(channel, base, [h | t]) do
      path = Path.join(base, h)
      :ssh_sftp.make_dir(channel, path)
      |> case do
        result when result in [:ok, {:error, :file_already_exists}] ->
          do_mkdir_p!(channel, path, t)
        other -> {:error, "could not create folder: #{inspect other}"}
      end
    end


    #Stores a file and returns {:ok, identifier} tuple
    defp do_store(config, file_source, options) do
      channel = Keyword.get(options, :channel)

      with {:ok, path} <- build_target_path(config, options),
        {:ok, path} <- create_target_file(channel, path, options),
        :ok <- copy_file(channel, file_source, path) do
          identifier = [path, config.directory]
            |> Enum.map(fn path -> Helpers.expand_path(path) end)
            |> (&(apply(Path, :relative_to, &1))).()
          {:ok, identifier}
        else
          any ->
            {:error, any}
        end
    end

    defp do_store_data(config, iodata, options) do
      channel = Keyword.get(options, :channel)

      with {:ok, path} <- build_target_path(config, options),
           {:ok, path} <- create_target_file(channel, path, options),
           :ok <- send_data(channel, iodata, path) do
        path = Helpers.expand_path(path)
        from = Helpers.expand_path(config.directory)
        identifier = Path.relative_to(path, from)
        {:ok, identifier}
      else
        any -> {:error, any}
      end
    end

    defp do_get_info(config, identifier, options) do
      channel = Keyword.get(options, :channel)
      path = Path.join(config.directory, identifier)

      with {:ok, stat} <- :ssh_sftp.read_file_info(channel, path) do
        hashes = get_remote_hashes(channel, path, Keyword.get(options, :hashes, []))
        url = case get_url(config, identifier, options) do
          {:ok, url} -> url
          other -> other
        end
        stat = File.Stat.from_record(stat)
        file_info = %Belt.FileInfo{
          config: config,
          identifier: identifier,
          url: url,
          hashes: hashes,
          size: stat.size,
          modified: stat.ctime
        }
        {:ok, file_info}
      end
    end

    def get_remote_hashes(_channel, _path, []), do: []
    def get_remote_hashes(channel, path, hashes) do
      with {:ok, {_window, packet_size}} <- :ssh_sftp.recv_window(channel) do
        packet_size = Enum.min([@stream_size, packet_size])
        stream = Stream.resource(
          fn ->
            {:ok, handle} = :ssh_sftp.open(channel, path, [:read])
            handle
          end,
          fn(handle) ->
            case :ssh_sftp.read(channel, handle, packet_size) do
              :eof -> {:halt, handle}
              {:ok, data} -> {[data], handle}
              {:error, _reason} -> {:halt, handle}
            end
          end,
          fn(handle) -> :ssh_sftp.close(channel, handle) end
        )
        Belt.Hasher.hash_stream(stream, hashes)
      end
    end

    defp copy_file(channel, source_path, target_path) do
      target_path = target_path |> String.to_charlist()
      file_opts = [:write, :binary]
      with true,
        {:ok, {_window, packet_size}} <- :ssh_sftp.send_window(channel),
        {:ok, handle} <- :ssh_sftp.open(channel, target_path, file_opts),
        packet_size = Enum.min([@stream_size, packet_size]),
        :ok <- do_copy_file(channel, handle, packet_size, source_path) do
        :ssh_sftp.close(channel, handle)
      end
    end

    defp do_copy_file(channel, handle, packet_size, source_path) do
      File.stream!(source_path, [:read], packet_size)
      |> Enum.reduce_while([], fn(data, acc) ->
          awrite_result = :ssh_sftp.awrite(channel, handle, data)
          case awrite_result do
            {:async, _n} -> {:cont, [awrite_result | acc]}
            other -> {:halt, other}
          end
        end)
      |> handle_async_replies()
    end

    defp handle_async_replies(reply_ids) when is_list(reply_ids) do
      Enum.reduce_while(reply_ids, :ok, fn({:async, n}, _acc) ->
        receive do
          {:async_reply, ^n, :ok} -> {:cont, :ok}
          {:async_reply, ^n, other} -> {:halt, other}
        end
      end)
    end

    defp send_data(channel, iodata, target_path) do
      target_path = String.to_charlist(target_path)
      file_opts = [:write, :binary]

      with {:ok, {_window, packet_size}} <- :ssh_sftp.send_window(channel),
           {:ok, handle} <- :ssh_sftp.open(channel, target_path, file_opts) do
        result = do_send_data(channel, handle, iodata, packet_size)
        :ssh_sftp.close(channel, handle)
        result
      end
    end

    defp do_send_data(channel, handle, iodata, packet_size) do
      iodata
      |> IO.iodata_to_binary()
      |> chunk_binary(packet_size)
      |> Enum.reduce_while([], fn data, acc ->
        case :ssh_sftp.awrite(channel, handle, data) do
          {:async, _n} = result -> {:cont, [result | acc]}
          other -> {:halt, other}
        end
      end)
      |> handle_async_replies()
    end

    defp chunk_binary(binary, byte_size, acc \\ [])

    defp chunk_binary(binary, byte_size, acc) when byte_size(binary) <= byte_size do
      Enum.reverse([binary | acc])
    end

    defp chunk_binary(binary, byte_size, acc) do
      <<chunk::size(byte_size), rest::binary>> = binary
      chunk_binary(rest, byte_size, [<<chunk::size(byte_size)>> | acc])
    end


    defp build_target_path(config, options) do
      dir = config.directory
      scope = Keyword.get(options, :scope, "")
      key = Keyword.get(options, :key)

      [dir, scope, key]
      |> Path.join()
      |> Helpers.ensure_included(dir)
    end

    defp create_target_file(channel, path, options) do
      mkdir_p!(channel, Path.dirname(path))
      {overwrite, max_renames} = case Keyword.get(options, :overwrite, :rename) do
        :rename -> {false, @max_renames}
        true -> {true, 0}
        _other -> {false, 0}
      end
      do_create_target_file(channel, path, overwrite, 0, max_renames)
    end

    defp do_create_target_file(channel, path, overwrite, renames, max_renames)

    defp do_create_target_file(channel, path, true, _renames, _max_renames) do
      case :ssh_sftp.open(channel, path, [:write]) do
        {:ok, handle} ->
          :ssh_sftp.close(channel, handle)
          {:ok, path}
        {:error, reason} -> {:error, reason}
      end
    end

    defp do_create_target_file(channel, path, _overwrite, renames, max_renames)
    when renames < max_renames do
      incremented_path = Helpers.increment_path(path, renames)

      case :ssh_sftp.read_file_info(channel, incremented_path) do
        {:error, :no_such_file} ->
          do_create_target_file(channel, incremented_path, true, renames, max_renames)
        _other ->
          do_create_target_file(channel, path, false, renames + 1, max_renames)
      end
    end

    defp do_create_target_file(_, _, _, _, _),
      do: {:error, "could not create target file"}
  end
end

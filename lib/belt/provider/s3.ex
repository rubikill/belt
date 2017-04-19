defmodule Belt.Provider.S3 do
  @moduledoc """
  Provider module offering support for S3-compatible storage services though
  `ExAws`.

  All S3-compatible services that use the v4 signature are supported,  e. g.
  *Amazon S3*, *EMC Elastic Cloud Storage* or *Minio*.

  ## Usage
  ```
  {:ok, config} = Belt.Provider.S3.new([…])
  {:ok, %FileInfo{}} = Belt.store(config, "/path/to/file.ext")
  ```

  ## Caveats
  Unlike `Belt.Provider.Filesystem` and `Belt.Provider.SFTP`,
  `Belt.Provider.S3` pre-calculates the hashes of a file before uploading it
  and stores them as metadata. This means that only hashes that were requested
  in the options for `Belt.store/3` can be retrieved later. If a service does
  not support storing metadata, hashes can not be retrieved.
  ```
  {:ok, file_info} = Belt.store(config, "/path/to/file.ext", hashes: [md5, sha])
  Belt.get_info(config, file_info.identifier, hashes: [md5, sha, sha256])
  #=> %{hashes: ["a1…ff", "d9…ca", :unavailable]}
  ```
  """

  use Belt.Provider
  alias Belt.Provider.Helpers

  @max_renames Belt.Config.get(__MODULE__, :max_renames)

  @typedoc """
  Options for creating an Filesystem provider.
  """
  @type s3_option ::
    {:access_key_id, String.t} |
    {:base_url, String.t} |
    {:bucket, String.t} |
    {:host, String.t} |
    {:https, boolean} |
    {:port, integer} |
    {:region, String.t} |
    {:secret_access_key, String.t}


  @doc """
  Creates a new S3 provider configuration.

  ## Examples
  ```
  #Defaults to Amazon S3 with the us-west-2 region
  iex> {:ok, config} = Belt.Provider.S3.new(access_key_id: "…", secret_access_key: "…")
  ...> {config.host, config.region}
  {"s3.dualstack.us-west-2.amazonaws.com", "us-west-2"}

  #When using Amazon S3, specifying a region will automatically set the host
  iex> {:ok, config} = Belt.Provider.S3.new(region: "eu-central-1", access_key_id: "…", secret_access_key: "…")
  ...> {config.host, config.region}
  {"s3.dualstack.eu-central-1.amazonaws.com", "eu-central-1"}
  ```

  ## Options
  - `access_key_id` (required) - `String.t`
  - `secret_access_key` (required) - `String.t`
  - `base_url` - `String.t`: :unavailable,
  - `host` - `String.t`: - Default: `s3.amazonaws.com`,
  - `region` - `String.t` - Default: `"us-west-2"`
  - `port` - `String.t`: - Default: 443,
  - `bucket` (required) - `String.t`,
  - `https` - `String.t`: - Default: true
  """
  @spec new([s3_option]) :: {:ok, Belt.Provider.configuration}
  def new(opts) do
    %Belt.Provider.S3.Config{}
    |> Map.to_list()
    |> Enum.map(fn {key, default} ->
      case key do
      :"__struct__" -> {key, default}
      _ -> {key, Keyword.get(opts, key, default)}
      end
    end)
    |> Enum.into(%{})
    |> determine_host()
    |> validate_config()
  end

  defp determine_host(config) do
    do_determine_host(config, config.host, config.region)
  end

  defp do_determine_host(config, host, region)
  when host in ["s3.amazonaws.com", nil] and is_binary(region),
    do: %{config | host: "s3.dualstack.#{region}.amazonaws.com"}

  defp do_determine_host(config, _host, _region), do: config

  defp validate_config(config) do
    {:ok, config}
  end


  @doc """
  Creates a new S3 provider configuration with default credentials.

  Default credentials can be set in multiple ways:
  1. In the `Mix.Config` application configuration
  2. Using the `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` environment
     variables
  3. Using AWS CLI config files through `ExAws`
  4. Configuring `ExAws` with `Mix.Config`

  ## Example application configuration
  ```
  #config.exs
  config :belt, Belt.Provider.S3,
    default: [access_key_id: "…",
              secret_access_key: "…",
              bucket: "…"]
  """
  @spec default([s3_option]) ::
    {:ok, Belt.Provider.configuration} |
    {:error, term}
  def default(options \\ []) do
    get_exaws_defaults()
    |> Keyword.merge(fetch_defaults())
    |> Keyword.merge(options)
    |> ensure_defaults_set()
  end

  defp get_exaws_defaults() do
    try do
      ExAws.Config.new(:s3)
      |> options_from_exaws()
    rescue
      _ -> []
    end
  end

  defp options_from_exaws(aws_config) do
    %Belt.Provider.S3.Config{}
    |> Map.delete(:"__struct__")
    |> Map.to_list()
    |> Enum.map(fn {key, default} ->
      case key do
        :https -> {key, (if aws_config.scheme == "http://", do: false, else: true)}
        _ -> {key, Map.get(aws_config, key, default)}
      end
    end)
  end

  defp fetch_defaults() do
    with {:ok, app_conf} <- Application.fetch_env(:belt, Belt.Provider.S3),
         {:ok, defaults} <- Keyword.fetch(app_conf, :default) do
         defaults
    else
      _ -> []
    end
  end

  defp ensure_defaults_set([]), do: {:error, :not_set}
  defp ensure_defaults_set(defaults), do: Belt.Provider.S3.new(defaults)


  @doc """
  Implementation of the `Belt.Provider.store/3` callback.
  """
  def store(config, file_source, options) do
    aws_config = get_aws_config(config, options)

    with {:ok, identifier} <- create_identifier(config, aws_config, options),
         {:ok, _} <- do_store(config, aws_config, identifier, file_source) do
         do_get_info(config, aws_config, identifier, options)
    end
  end

  defp do_store(config, aws_config, identifier, file_source) do
    requested_hashes = [:md5, :sha, :sha256]
    hashes = Belt.Hasher.hash_file(file_source, requested_hashes)
    meta_opts = Enum.zip(requested_hashes, hashes)
      |> Enum.map(fn({key, val}) -> {"belt-hash-#{key}", val} end)

    ExAws.S3.Upload.stream_file(file_source)
    |> ExAws.S3.upload(config.bucket, identifier, meta: meta_opts)
    |> ExAws.request(aws_config)
  end

  defp create_identifier(config, aws_config, options) do
    scope = case Keyword.get(options, :scope) do
      scope when is_binary(scope) -> scope
      _other -> ""
    end
    key = Keyword.get(options, :key)
    identifier = Path.join(["/", scope, key])
      |> Helpers.expand_path()

    case Keyword.get(options, :overwrite, :rename) do
      true -> {:ok, identifier}
      :rename -> do_create_identifier(config, aws_config, identifier, 0, @max_renames)
      _other ->  do_create_identifier(config, aws_config, identifier, 0, 0)
    end
    |> case do
      {:ok, identifier} -> {:ok, identifier |> Path.relative_to("/")}
      other -> other
    end
  end

  defp do_create_identifier(config, aws_config, identifier, renames, max_renames)
  when renames < max_renames do
    incremented_identifier = Helpers.increment_path(identifier, renames)

    ExAws.S3.head_object(config.bucket, incremented_identifier)
    |> ExAws.request(aws_config)
    |> case do
      {:error, {:http_error, 404, _}} ->
        {:ok, incremented_identifier}
      _other ->
        do_create_identifier(config, aws_config, identifier, renames + 1, max_renames)
    end
  end

  defp do_create_identifier(_, _, _, _, _),
    do: {:error, "could not create target file"}


  @doc """
  Implementation of the `Belt.Provider.delete/3` callback.
  """
  def delete(config, identifier, options) do
    aws_config = get_aws_config(config, options)
    ExAws.S3.delete_object(config.bucket, identifier)
    |> ExAws.request(aws_config)
    |> case do
      {:ok, _} -> :ok
      _other   -> :ok
    end
  end


  @doc """
  Implementation of the Provider.delete_all/2 callback.
  """
  def delete_all(config, options) do
    aws_config = get_aws_config(config, options)
    operation = ExAws.S3.list_objects(config.bucket)
    delete_files(config, aws_config, operation)
  end


  @doc """
  Implementation of the Provider.delete_scope/3 callback.
  """
  def delete_scope(config, scope, options) do
    with {:ok, scope} <- Helpers.ensure_included(Path.join("/", scope), "/") do
      scope = Path.relative_to(scope, "/")
      aws_config = get_aws_config(config, options)
      operation = ExAws.S3.list_objects(config.bucket, prefix: scope)
      delete_files(config, aws_config, operation)
    else
      _ -> {:error, :invalid_scope}
    end
  end

  defp delete_files(config, aws_config, operation) do
    ExAws.stream!(operation, aws_config)
    |> Stream.map(&(&1[:key]))
    |> Stream.chunk(1000, 1000, [])
    |> Enum.each(fn(files) ->
      ExAws.S3.delete_multiple_objects(config.bucket, files)
      |> ExAws.request!(aws_config)
    end)
  end


  @doc """
  Implementation of the `Belt.Provider.get_info/3` callback.
  """
  def get_info(config, identifier, options) do
    aws_config = get_aws_config(config, options)
    do_get_info(config, aws_config, identifier, options)
  end

  defp do_get_info(config, aws_config, identifier, options) do
    request = ExAws.S3.head_object(config.bucket, identifier)
    with {:ok, %{headers: headers}} <- ExAws.request(request, aws_config) do
      headers = parse_file_info_header(headers, [])

      hashes = get_hashes(headers, options)

      file_info = struct(%Belt.FileInfo{}, headers)
        |> Map.put(:identifier, identifier)
        |> Map.put(:config, config)
        |> Map.put(:hashes, hashes)
        |> Map.put(:url, :unavailable)
        |> Map.put(:hashes, hashes)
      {:ok, file_info}
    end
  end

  defp parse_file_info_header([{"Content-Length", size} | t], acc) do
    acc = [{:size, String.to_integer(size)} | acc]
    parse_file_info_header(t, acc)
  end

  defp parse_file_info_header([{"Last-Modified", date} | t], acc) do
    [_, dd, mm, yyyy, time, _tz] = String.split(date, " ")
    dd = dd |> String.to_integer()
    yyyy = yyyy |> String.to_integer()
    mm = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct",
          "Nov", "Dec"]
      |> Enum.find_index(fn(str) -> str == mm end)
    [hh, mins, ss] = String.split(time, ":")
      |> Enum.map(fn(n) -> String.to_integer(n) end)

    acc = [{:modified, {{yyyy, mm, dd}, {hh, mins, ss}}} | acc]
    parse_file_info_header(t, acc)
  end

  defp parse_file_info_header([{"x-amz-meta-belt-hash-" <> hash_name, hash} | t], acc) do
    pair = {hash_name, hash}
    acc = Keyword.update(acc, :hashes, [pair], fn(hashes) ->
      [pair | hashes]
    end)
    parse_file_info_header(t, acc)
  end

  defp parse_file_info_header([_ | t], acc), do: parse_file_info_header(t, acc)
  defp parse_file_info_header([], acc), do: acc

  defp get_hashes(headers, options) do
    header_hashes = Keyword.get(headers, :hashes, [])
    Keyword.get(options, :hashes, [])
    |> Enum.map(&extract_header_hash(&1, header_hashes))
  end

  defp extract_header_hash(hash, header_hashes) do
    hash = hash |> to_string()
    Enum.find_value(header_hashes, :unavailable, fn(pair) ->
      case pair do
        {^hash, value} -> value
        _other -> nil
      end
    end)
  end


  @doc """
  Implementation of the `Belt.Provider.get_url/3` callback.

  ## Provider-specific options
  - `presign` - `boolean`
  """
  def get_url(config, identifier, options) do
    case options[:presign] do
      true   -> get_presigned_url(config, identifier, options)
      _other -> do_get_url(config, identifier, options)
    end
  end

  defp get_presigned_url(config, identifer, options) do
    aws_config = get_aws_config(config, options)
    ExAws.S3.presigned_url(aws_config, :get, config.bucket, identifer)
    |> case do
      {:ok, url} -> {:ok, url}
      _other -> {:error, "could not retrieve presigned url"}
    end
  end

  defp do_get_url(config, identifier, _options) do
    base_url = case config.base_url do
      base_url when is_binary(base_url) -> base_url
      _ ->
        schema = if config.https == false, do: "http://", else: "https://"
        schema <> config.host <> ":" <> "#{config.port}" <> "/"
    end
    url = URI.merge(base_url, identifier) |> URI.to_string()
    {:ok, url}
  end


  @doc """
  Implementation of the `Belt.Provider.list_files/2` callback.
  """
  def list_files(config, options) do
    aws_config = get_aws_config(config, options)
    ExAws.S3.list_objects(config.bucket)
    |> ExAws.request(aws_config)
    |> do_list_files()
  end

  defp do_list_files({:ok, %{body: %{contents: contents}}}) do
    identifiers = contents
      |> Enum.map(fn(file_data) -> file_data[:key] end)
    {:ok, identifiers}
  end

  defp do_list_files(_), do: {:error, "could not retrieve file list"}


  #Returns configuration for ExAws
  defp get_aws_config(config, _options) do
    options = [host: config.host,
      port: config.port,
      scheme: get_scheme(config),
      access_key_id: config.access_key_id,
      secret_access_key: config.secret_access_key,
      region: config.region
    ]
    ExAws.Config.new(:s3, options)
  end

  defp get_scheme(%{https: https}) when https == false, do: "http://"
  defp get_scheme(_), do: "https://"
end

defmodule Belt.Test.Provider.S3.Helper do
  require Logger

  defp fetch_var(var) do
    Application.fetch_env(:belt, Belt.Test.Provider.S3)
    |> case do
      :error -> fetch_env_var(var)
      {:ok, vals} ->
        case vals[var] do
          nil -> fetch_env_var(var)
          val -> val
        end
    end
  end

  defp fetch_env_var(var) do
    env_var = "BELT_TEST_S3_#{var}" |> String.upcase()
    case System.get_env(env_var) do
      nil ->
        {:error,
         "Set \"config :belt, Belt.Test.Provider.S3, #{var}: val\" "<>
         "or environment variable \"#{env_var}\""}
      "true" -> true
      "false" -> false
      val ->
        case Integer.parse(val) do
          :error -> val
          {num, _} -> num
        end
    end
  end

  def config_opts(_context) do
    vars = [:host, :region, :access_key_id, :secret_access_key, :port, :bucket, :https]
    vals = vars |> Enum.map(&fetch_var(&1))

    errors = Enum.reduce(vals, [], fn(val, acc) ->
      case val do
        {:error, message} -> [message | acc]
        _ -> acc
      end
    end)

    if Enum.empty?(errors),
      do: Enum.zip(vars, vals),
      else: {:error, Enum.join(errors, "\n")}
  end

  def skip?() do
    case config_opts([]) do
      {:error, message} ->
        """
        Missing test configuration for Belt.Provider.S3.
        #{message}
        Skipping tests.
        """
        |> Logger.debug()
        true
      _other -> false
    end
  end
end

defmodule Belt.Test.Provider.S3 do
  use Belt.Test.Provider,
    provider: Belt.Provider.S3,
    skip: Belt.Test.Provider.S3.Helper.skip?()

    def config_opts(context),
      do: Belt.Test.Provider.S3.Helper.config_opts(context)

  test "get presigned url",
      %{provider: provider, _files: [file | _]} = context do
    {:ok, config} = provider.new(config_opts(context))
    {:ok, %{identifier: identifier}} = Belt.store(config, file)

    {:ok, url} = Belt.get_url(config, identifier, presign: true)
    uri = URI.parse(url)

    assert uri.host != nil
    assert uri.scheme in ["http", "https"]
    assert uri.path != nil
  end

  test "get default config" do
    key_id = "foo"
    access_key = "bar"
    key_id2 = "foo2"
    access_key2 = "bar2"

    #Defaults from ExAws
    Application.put_env(:ex_aws, :access_key_id, key_id)
    Application.put_env(:ex_aws, :secret_access_key, access_key)
    {:ok, config} = Belt.Provider.S3.default(bucket: "test")
    assert config.access_key_id == key_id
    assert config.secret_access_key == access_key

    #Defaults from Belt config
    Application.put_env(:belt, Belt.Provider.S3, default: [
      access_key_id: key_id2,
      secret_access_key: access_key2
    ])
    {:ok, config} = Belt.Provider.S3.default(bucket: "test")
    assert config.access_key_id == key_id2
    assert config.secret_access_key == access_key2
  end
end

use Mix.Config

config :belt,
  providers: [Belt.Provider.Filesystem,
              Belt.Provider.SFTP,
              Belt.Provider.S3],
  timeout: 10_000,
  max_concurrency: 20,
  stream_size: 1_048_576, #1 MiB
  max_renames: 10

config :belt, Belt.Hasher,
  stream_size: 1_048_576 #1 MiB

env_config_file = Path.join(__DIR__, "#{Mix.env}.exs") |> Path.expand()
if File.exists?(env_config_file), do: import_config(env_config_file)

defmodule Belt.Test.Provider.Filesystem do
  use Belt.Test.Provider,
    provider: Belt.Provider.Filesystem

  setup_all do
    dir = create_tmp_dir()

    on_exit(fn -> File.rm_rf(dir) end)

    {:ok, dir: dir}
  end

  def config_opts(%{dir: dir}) do
    [directory: dir,
     base_url: "http://example.com/files/"]
  end
end

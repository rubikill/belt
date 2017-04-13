defmodule Belt.Test.Provider do
  defmacro __using__(options) do
    quote do
      use ExUnit.Case
      doctest unquote(options)[:provider]

      @moduletag unquote(options)

      defp config_opts(context), do: []
      defoverridable [config_opts: 1]

      defp create_tmp_dir() do
        time = System.os_time()
        partial = "#{__MODULE__}-#{time}"
        dir = System.tmp_dir!()
        |> Path.join(partial)

        File.mkdir_p(dir)

        dir
      end

      setup_all do
        files = for n <- 0..5 do
          time = System.os_time()
          tmp_dir = System.tmp_dir!()
          partial = "#{__MODULE__}-file-#{time}"
          path = Path.join(tmp_dir, partial)

          File.open!(path, [:write, :binary, :raw], fn(file) ->
            no_lines = 1000 + :rand.uniform(1000)
            for _ <- 0..no_lines do
              line_data =  "FILE#{n}\n"
              IO.binwrite(file, line_data)
            end
          end)
          path
        end

        on_exit(fn ->
          for file <- files, do: File.rm!(file)
        end)

        {:ok, _files: files}
      end

      setup context do
        case config_opts(context) do
          {:error, message} -> flunk(message)
          _other -> {:ok, []}
        end
      end

      test "create configuration",
          %{provider: provider, _files: files} = context do
        assert {:ok, %{}} = provider.new(config_opts(context))
      end

      test "store a file",
          %{provider: provider, _files: [file | _]} = context do
        {:ok, config} = provider.new(config_opts(context))

        assert {:ok, %Belt.FileInfo{}} = Belt.store(config, file)
      end

      test "store a file asynchronously",
          %{provider: provider, _files: [file | _]} = context do
        {:ok, config} = provider.new(config_opts(context))

        assert {:ok, job_id} = Belt.store_async(config, file)
        assert {:ok, {:ok, %Belt.FileInfo{}}} = Belt.Job.await_and_shutdown(job_id)
      end

      test "delete a file",
          %{provider: provider, _files: [file | _]} = context do
        {:ok, config} = provider.new(config_opts(context))
        {:ok, %{identifier: identifier}} = Belt.store(config, file)

        assert :ok = Belt.delete(config, identifier)
      end

      test "get file info",
          %{provider: provider, _files: [file | _]} = context do
        {:ok, config} = provider.new(config_opts(context))
        {:ok, %{identifier: identifier}} = Belt.store(config, file)

        assert {:ok, %Belt.FileInfo{}} = Belt.get_info(config, identifier)
      end

      test "get file url",
          %{provider: provider, _files: [file | _]} = context do
        {:ok, config} = provider.new(config_opts(context))
        {:ok, %{identifier: identifier}} = Belt.store(config, file)
        {:ok, url} = Belt.get_url(config, identifier)
        uri = URI.parse(url)

        assert uri.host != nil
        assert uri.scheme in ["http", "https"]
        assert uri.path != nil
      end

      test "rename on key conflict",
          %{provider: provider, _files: [file1, file2 | _]} = context do
        {:ok, config} = provider.new(config_opts(context))
        key = "rename-test.tmp"
        {:ok, %{identifier: identifier1}} = Belt.store(config, file1, overwrite: :rename)
        {:ok, %{identifier: identifier2}} = Belt.store(config, file2, overwrite: :rename)

        refute identifier1 == identifier2
      end

      test "overwrite on key conflict",
          %{provider: provider, _files: [file1, file2 | _]} = context do
        {:ok, config} = provider.new(config_opts(context))
        key = "rename-test.tmp"
        {:ok, file_info1} = Belt.store(config, file1, key: key, overwrite: true, hashes: [:md5])
        %{identifier: identifier1,
          hashes: [md51]} = file_info1
        {:ok, file_info2} = Belt.store(config, file2, key: key, overwrite: true, hashes: [:md5])
        %{identifier: identifier2,
          hashes: [md52]} = file_info2
        {:ok, file_info_final} = Belt.get_info(config, identifier1, hashes: [:md5])
        %{hashes: [md5_final]} = file_info_final

        assert identifier1 == identifier2
        assert md52 == md5_final
      end

      test "retrieving hashes",
          %{provider: provider, _files: [file1 | _]} = context do
        {:ok, config} = provider.new(config_opts(context))
        key = "hash.tmp"
        {:ok, file_info} = Belt.store(config, file1, key: key, hashes: [:md5, :sha, :sha256])
        %{identifier: identifier,
          hashes: hashes} = file_info

        refute :unavailable in hashes
        assert {:ok, %{hashes: ^hashes}} = Belt.get_info(config, identifier, hashes: [:md5, :sha, :sha256])
      end

      test "error on key conflict with overwrite: false",
          %{provider: provider, _files: [file1, file2 | _]} = context do
        {:ok, config} = provider.new(config_opts(context))
        key = "no-rename-test.tmp"
        {:ok, file_info} = Belt.store(config, file1, key: key, hashes: [:md5])
        %{identifier: identifier,
          hashes: [md5]} = file_info

        assert {:error, _} = Belt.store(config, file2, key: key, overwrite: false)
        assert {:ok, %{hashes: [^md5]}} = Belt.get_info(config, identifier, hashes: [:md5])
      end

      test "list files",
          %{provider: provider, _files: [file | _]} = context do
        {:ok, config} = provider.new(config_opts(context))
        key = "list-files-test.tmp"
        {:ok, %{identifier: identifier}} = Belt.store(config, file, key: key)

        assert {:ok, files_list} = Belt.list_files(config)
        assert identifier in files_list
      end

      test "list files with scoped file",
          %{provider: provider, _files: [file | _]} = context do
        {:ok, config} = provider.new(config_opts(context))
        key = "list-files-scoped-test.tmp"
        {:ok, %{identifier: identifier}} = Belt.store(config, file, key: key, scope: "list-scope")

        assert {:ok, files_list} = Belt.list_files(config)
        assert identifier in files_list
      end
    end
  end
end

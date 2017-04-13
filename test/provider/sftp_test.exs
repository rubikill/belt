defmodule Belt.Test.Provider.SFTP do
  use Belt.Test.Provider,
    provider: Belt.Provider.SFTP

  @daemon_host "localhost"
  @daemon_port 8900
  @user "edna"
  @password "Th31maElłen"

  setup_all do
    dir = create_tmp_dir()
    storage_dir = Path.join(dir, "storage")
    config_dir = Path.join(dir, "config")
    [storage_dir, config_dir] |> Enum.each(&File.mkdir(&1))

    #Create host key
    key_path = Path.join(config_dir, "ssh_host_rsa_key")
    System.cmd("ssh-keygen", ["-t", "rsa", "-N", "", "-f", key_path])
    host_key = load_public_key(key_path <> ".pub")

    #Create user key
    user_key_path = Path.join(config_dir, "ssh_user_key")
    System.cmd("ssh-keygen", ["-t", "rsa", "-N", "", "-f", user_key_path])
    File.cp(user_key_path <> ".pub", Path.join(config_dir, "authorized_keys"))
    user_key = load_key(user_key_path)
    #:timer.sleep 5000

    #SSH Daemon configuration
    passwords = [{@user |> to_charlist(), @password |> to_charlist()}]
    subsystem_spec = :ssh_sftpd.subsystem_spec(
      cwd: storage_dir |> String.to_charlist(),
      root: storage_dir |> String.to_charlist())
    ssh_daemon_opts = [subsystems: [subsystem_spec],
      system_dir: config_dir |> to_charlist(),
      user_dir: config_dir |> to_charlist(),
      user_passwords: passwords
    ]

    :ssh.start()
    {:ok, ssh_daemon} = :ssh.daemon(@daemon_port, ssh_daemon_opts)

    on_exit(fn ->
      :ssh.stop_daemon(ssh_daemon)
      File.rm_rf(dir)
    end)

    {:ok, dir: dir, host_key: host_key, user_key: user_key}
  end

  def config_opts(_context) do
    [host: @daemon_host,
     user: @user,
     password: @password,
     port: @daemon_port,
     verify_host_key: false,
     base_url: "https://example.org"]
  end


  @pem_regex ~r/[-]+BEGIN RSA PRIVATE KEY.*END RSA PRIVATE KEY[-]+\n/s
  defp load_key(path) do
    file_contents = File.read!(path)
    Regex.run(@pem_regex, file_contents)
    |> List.first()
    |> :public_key.pem_decode()
    |> List.first()
    |> :public_key.pem_entry_decode()
  end

  defp load_public_key(path) do
    File.read!(path)
    |> :public_key.ssh_decode(:public_key)
    |> List.first()
    |> elem(0)
  end


  test "using keys",
      %{provider: provider, host_key: host_key, user_key: user_key} = context do

    host_key = :public_key.ssh_hostkey_fingerprint(:sha256, host_key)
      |> to_string()

    user_key = [:public_key.pem_entry_encode(:RSAPrivateKey, user_key)]
      |> :public_key.pem_encode()
      |> to_string()

    config_opts = config_opts(context)
    |> Keyword.delete(:user)
    |> Keyword.delete(:password)
    |> Keyword.put(:user_key, user_key)
    |> Keyword.put(:verify_host_key, true)
    |> Keyword.put(:host_key, host_key)
    {:ok, config} = provider.new(config_opts)

    assert {:ok, _} = Belt.list_files(config)
  end
end

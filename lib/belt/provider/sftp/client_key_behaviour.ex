if Code.ensure_loaded? :ssh_sftp do
  defmodule Belt.Provider.SFTP.ClientKeyBehaviour do
    @moduledoc """
    Implements the `:ssh_client_key_api` behaviour for Belt.Provider.SFTP
    """

    @behaviour :ssh_client_key_api

    @pem_regex ~r/[-]+BEGIN RSA PRIVATE KEY.*END RSA PRIVATE KEY[-]+\n/s

    @doc """
    Dynamically adding host keys is not supported
    """
    def add_host_key(_host_names, _key, _connect_options) do
      {:error, :not_implemented}
    end


    @doc """
    Verifies host keys if enabled through `verify_host_key` in `key_cb_private`.

    Otherwise accepts all keys
    """
    def is_host_key(key, host, :"ssh-rsa", connect_options) do
      key_cb_private = Keyword.get(connect_options, :key_cb_private, [])
      case Keyword.get(key_cb_private, :verify_host_key) do
        falsy when falsy in [nil, false] -> true
        _ ->
          expected_key = Keyword.get(key_cb_private, :host_key, nil)
          host = host |> to_string()
          keys_match?(key, host, expected_key, host)
      end
    end

    def is_host_key(_, _, _, _), do: {:error, "algorithm not supported"}

    defp keys_match?(key, host, {:RSAPublicKey, _, _} = expected_key, host) do
      key == expected_key
    end

    defp keys_match?(key, host, fingerprint, host) do
      expected_fp = fingerprint |> to_string()
      fp = key
        |> get_fp(expected_fp)
        |> to_string
      fp == expected_fp
    end

    defp get_fp(key, "MD5:" <> _),
      do: :public_key.ssh_hostkey_fingerprint(:md5, key)

    defp get_fp(key, "SHA1:" <>  _),
      do: :public_key.ssh_hostkey_fingerprint(:sha, key)

    defp get_fp(key, "SHA256:" <>  _),
      do: :public_key.ssh_hostkey_fingerprint(:sha256, key)

    defp get_fp(key, expected_fp) when is_binary(expected_fp),
      do: :public_key.ssh_hostkey_fingerprint(key)


    @doc """
    Processes and returns `user_key` if provided in `key_cb_private`.

    Otherwise generates one-time private key.
    """
    def user_key(:"ssh-rsa", connect_options) do
      key_cb_private = Keyword.get(connect_options, :key_cb_private, [])
      key = case Keyword.get(key_cb_private, :user_key) do
        nil -> genrsa()
        pem when is_binary(pem) -> decode_user_key(pem)
        key -> key
      end
      {:ok, key}
    end

    def user_key(_, _), do: {:error, "algorithm not supported"}


    @doc """
    Creates a new `:public_key.private_key` record by calling `openssl`.
    """
    def genrsa(bytes \\ 2048) do
      openssl_output = :os.cmd('openssl genrsa #{bytes}') |> to_string()
      Regex.run(@pem_regex, openssl_output)
      |> List.first()
      |> decode_user_key()
    end

    defp decode_user_key(pem) do
      pem
      |> :public_key.pem_decode()
      |> List.first()
      |> :public_key.pem_entry_decode()
    end
  end
end

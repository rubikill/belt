defmodule Belt.Provider.SFTP.Config do
    @moduledoc false
    defstruct(
        host: nil,
        port: 22,
        user: nil,
        password: nil,
        user_key: nil,
        host_key: nil,
        verify_host_key: true,
        directory: ".",
        base_url: nil,
        provider: Belt.Provider.SFTP
    )
end

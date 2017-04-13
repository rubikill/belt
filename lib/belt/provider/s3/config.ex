defmodule Belt.Provider.S3.Config do
    @moduledoc false
    defstruct(
        provider: Belt.Provider.S3,
        access_key_id: nil,
        secret_access_key: nil,
        base_url: nil,
        host: nil,
        region: "us-west-2",
        port: 443,
        bucket: nil,
        https: true
    )
end

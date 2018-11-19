Support Ecto SQL 3.0

# Belt
[![Hex.pm](https://img.shields.io/hexpm/v/belt.svg)](https://hex.pm/packages/belt)
[![Hexdocs.pm](https://img.shields.io/badge/hexdocs-release-blue.svg)](https://hexdocs.pm/belt/getting-started.html)
[![License](https://img.shields.io/hexpm/l/belt.svg)](https://bitbucket.org/pentacent/belt/src/master/LICENSE)
[![Build Status](https://img.shields.io/bitbucket/pipelines/pentacent/belt.svg)](https://bitbucket.org/pentacent/belt/addon/pipelines/home)

Extensible Elixir OTP Application for storing files remotely or locally through
a unified API. Backends currently exist for the local filesystem, SFTP and
the Amazon S3 API.


## Documentation
Check out [the documentation at hexdocs.pm/belt](https://hexdocs.pm/belt) and our [Getting Started guide](https://hexdocs.pm/belt/getting-started.html).


## Usage
```elixir
#Simple file upload
{:ok, config} = Belt.Provider.SFTP.new(host: "example.com", directory: "/var/files",
                                       user: "…", password: "…")
Belt.store(config, "/path/to/local/file.ext")
#=> {:ok, %Belt.FileInfo{…}}


#Asynchronous file upload
{:ok, config} = Belt.Provider.S3.new(access_key_id: "…", secret_access_key: "…",
                                     bucket: "belt-file-bucket")
{:ok, job} = Belt.store_async(config, "/path/to/local/file.ext")
#Do other things while Belt is uploading in the background
Belt.await(job)
#=> {:ok, %Belt.FileInfo{…}}
```


## Installation
Belt can be installed by adding `belt` to your dependencies and application
list in `mix.exs`:

```elixir
def deps do
  [{:belt, "~> 0.1.0"}]
end

def application do
  [extra_applications: [:belt]]
end
```

### Installation for the S3 backend
If you want to use the S3 backend, you also need to add [ExAws](https://github.com/ex-aws/ex_aws/) with [ExAws S3](https://github.com/ex-aws/ex_aws_s3) as well as [Hackney](https://hex.pm/packages/hackney) and [sweet_xml](https://hex.pm/packages/sweet_xml) (which are required by ExAws) to your dependencies and applications list:
```elixir
def deps do
  [{:belt, "~> 0.4.0"},
   {:ex_aws, "~> 2.1"},
   {:ex_aws_s3, "~> 2.0"},
   {:hackney, "~> 1.9"},
   {:sweet_xml, "~> 0.6"}]
end

def application do
  [extra_applications: [:belt, :hackney, .sweet_xml]]
end
```

## License
Belt is dual-licensed and can be used under the terms of either the [GNU AGPLv3](https://www.gnu.org/licenses/agpl-3.0.en.html) or the [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0.html) license (which is the license Elixir uses).

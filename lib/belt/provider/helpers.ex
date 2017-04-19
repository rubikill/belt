defmodule Belt.Provider.Helpers do
  @moduledoc """
  Provides functions shared across providers.
  """

  @special_extension_regex ~r/(.*)(\.tar\.(?:gz|bz2|bz|xz)$)/

  @doc """
  Increments a key name.

  Returns the given `key` incremented by `increment` steps using an optional `fun`.
  `fun` receives the parameters `base`, `ext` and `increment`.

  ## Examples
  ```
  iex> increment_key("foo.tar.gz", 1)
  "foo_1.tar.gz"
  ```

  ```
  iex> increment_key("foo.bar", 0)
  "foo.bar"
  ```

  ```
  iex> increment_key("foo", 1)
  "foo_1"
  ```

  ```
  iex> increment_key("foo.bar", 1, fn(base, ext, increment) ->
  ...>   base <> ext <> " (\#{increment})"
  ...> end)
  "foo.bar (1)"
  ```
  """
  @spec increment_key(String.t, integer, (String.t, String.t, integer -> String.t)) :: String.t
  def increment_key(key, increment, fun \\ &( &1 <> "_#{&3}" <> &2 ))

  def increment_key(key, 0, _fun), do: key

  def increment_key(key, increment, fun) do
    {base, ext} = split_key(key)
    fun.(base, ext, increment)
  end

  @doc """
  Splits a key into its base name and extension.

  Unlike `Path.extname`, this also accounts for composite extensions such as *.tar.gz*.

  Returns `{base, ext}` tuple.

  ## Examples
  ```
  iex> split_key("foo.bar")
  {"foo", ".bar"}
  ```
  ```
  iex> split_key("foo.tar.gz")
  {"foo", ".tar.gz"}
  ```
  """
  @spec split_key(String.t) :: {String.t, String.t}
  def split_key(key) do
    case Regex.run(@special_extension_regex, key) do
      [_, base, ext] -> {base, ext}
      _other ->
      ext = Path.extname(key)
      base = Path.basename(key, ext)
      {base, ext}
    end
  end

  @doc """
  Increments the key part of a path.

  ## Example
  ```
  iex> increment_path("/foo/bar.ext", 1)
  "/foo/bar_1.ext"
  ```
  """
  @spec increment_path(Path.t, integer) :: Path.t
  def increment_path(path, increments) do
    dir = Path.dirname(path)
    key = Path.basename(path)
      |> increment_key(increments)
    Path.join(dir, key)
  end

  @doc """
  Ensures `path` is included in a `directory`.

  Returns the original path as `{:ok, path}` or an error tuple.

  ## Example
  ```
  iex> ensure_included("/foo/bar/buzz", "/foo/bar")
  {:ok, "/foo/bar/buzz"}
  ```
  ```
  iex> ensure_included("./foo", ".")
  {:ok, "./foo"}
  ```
  ```
  iex> {:error = s, _reason} = ensure_included("/usr", "."); s
  :error
  ```
  """
  @spec ensure_included(Path.t, Path.t) :: {:ok, Path.t} | {:error, term}
  def ensure_included(path, directory) when path == directory, do: path
  def ensure_included(path, directory) do
    path = expand_path(path)
    directory = expand_path(directory)
    if Path.relative_to(path, directory) != path,
      do: {:ok, path},
      else: {:error, "#{inspect path} is not included in #{inspect directory}"}
  end

  @spec expand_path(Path.t) :: Path.t
  def expand_path(path) do
    path
    |> Path.split()
    |> Enum.reduce([], fn(segment, acc) ->
      case segment do
        "." when acc == [] -> ["."]
        "." -> acc
        ".." ->
          case acc do
            [] -> [".."]
            [_ | []] -> [".."]
            [".." | t] -> [".." | acc]
            [_ | t] -> t
          end
        other -> [other | acc]
      end
    end)
    |> Enum.reverse()
    |> Path.join()
  end

  @doc """
  Creates a `Belt.FileInfo` struct from a local file.
  """
  @spec get_local_file_info(Path.t, list) :: %Belt.FileInfo{}
  def get_local_file_info(path, hashes \\ []) do
    %{size: size, ctime: modified} = File.stat!(path)
    hashes = Belt.Hasher.hash_file(path, hashes)

    %Belt.FileInfo{
      size: size,
      modified: modified,
      hashes: hashes
    }
  end

end

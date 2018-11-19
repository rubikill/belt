defmodule Belt.Test.Ecto.Config do
  use ExUnit.Case
  alias Belt.Ecto.Config

  test "cast" do
    config = get_config!()
    serialized_config = get_serialized_config!()
    assert Config.cast(config) == {:ok, config}
    assert Config.cast(serialized_config) == :error
    assert Config.cast(%{some_key: :foo}) == :error
    assert Config.cast(nil) == :error
  end

  test "cast!" do
    config = get_config!()
    assert Config.cast!(config)

    assert_raise FunctionClauseError, fn ->
      Config.cast!(%{some_key: :foo})
    end

    assert_raise FunctionClauseError, fn ->
      Config.cast!(nil)
    end
  end

  test "load" do
    config = get_config!()
    serialized_config = get_serialized_config!()
    assert Config.load(serialized_config) == {:ok, config}
    assert Config.load("") == :error
  end

  test "dump" do
    config = get_config!()
    serialized_config = get_serialized_config!()
    assert Config.dump(config) == {:ok, serialized_config}
    assert Config.dump(serialized_config) == :error
  end

  defp get_config!() do
    {:ok, config} = Belt.Provider.Filesystem.new(directory: ".", base_url: "https://example.org/")
    config
  end

  defp get_serialized_config!() do
    %{
      "provider" => "belt_atom::Elixir.Belt.Provider.Filesystem",
      "directory" => ".",
      "base_url" => "https://example.org/"
    }
  end
end

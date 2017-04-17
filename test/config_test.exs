defmodule Belt.Test.Config do
  use ExUnit.Case, async: true
  doctest Belt.Config

  setup_all do
    Application.put_env(:belt, :test_key, :foo)
    Application.put_env(:belt, :test_key2, :bar)
    Application.put_env(:belt, :test_module, test_key: :test)
  end

  test "retrieve value" do
    assert Belt.Config.get(:test_key) == :foo
  end


  test "retrieve module value" do
    assert Belt.Config.get(:test_module, :test_key) == :test
  end

  test "default to global value" do
    assert Belt.Config.get(:test_module, :test_key2) == :bar
  end

  test "raise on unset values" do
    assert_raise RuntimeError, fn ->
      Belt.Config.get(:test_unset_key)
    end

    assert_raise RuntimeError, fn ->
      Belt.Config.get(:test_module, :test_unset_key)
    end
  end
end

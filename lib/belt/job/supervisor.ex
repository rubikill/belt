defmodule Belt.Job.Supervisor do
  @moduledoc """
  Supervisor for `Belt.Job` processes.
  """

  use Supervisor

  def start_link() do
    Supervisor.start_link(__MODULE__, :ok, [name: __MODULE__])
  end

  def init(:ok) do
    children = [
      worker(Belt.Job, [], restart: :transient)
    ]
    supervise(children, strategy: :simple_one_for_one)
  end

  @doc """
  Starts a new `Belt.Job` process with the given payload and supervises it.
  When `name` is set to `:auto` or omitted, a name for the process will be
  generated automatically.
  """
  @spec start_child(term, term | :auto) :: {:ok, Belt.Job.t} | {:error, term}
  def start_child(payload, name \\ :auto) do
    name = case name do
      :auto -> :erlang.unique_integer([:positive])
      other -> other
    end

    Supervisor.start_child(__MODULE__, [name, payload])
    |> case do
      {:ok, _pid} -> {:ok, name}
      other -> {:error, other}
    end
  end
end

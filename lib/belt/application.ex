defmodule Belt.Application do
  @moduledoc false

  use Application
  import Supervisor.Spec

  def start(_type, _args) do
    children = [
      supervisor(Belt.Job.Supervisor, [], []),
      worker(Registry, [:unique, Belt.Job.Registry]),
      worker(Belt, [], []) |
      get_provider_supervisors()
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Belt.Supervisor)
  end

  defp get_provider_supervisors() do
    Application.fetch_env!(:belt, :providers)
    |> Enum.map(fn(provider) ->
      :"#{provider}.Supervisor"
      |> supervisor([], [])
    end)
  end
end

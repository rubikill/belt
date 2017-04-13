defmodule Belt.Provider.Supervisor do
  @moduledoc false
  defmacro __using__(_opts) do
    quote do
      defmodule Supervisor do
        @moduledoc false
        use ConsumerSupervisor

        @concurrency_limit 3

        def start_link() do
          children = [
            worker(get_worker_name(), [], restart: :temporary)
          ]
          opts = [
            strategy: :one_for_one,
            subscribe_to: [{Belt,
              max_demand: @concurrency_limit,
              min_demand: Integer.floor_div(@concurrency_limit, 2),
              partition: get_worker_name()
            }],
            name: __MODULE__
          ]
          ConsumerSupervisor.start_link(children, opts)
        end

        defp get_worker_name() do
          __MODULE__
          |> to_string()
          |> String.split(".")
          |> Enum.drop(-1)
          |> Enum.join(".")
          |> String.to_existing_atom()
        end
      end
    end
  end
end

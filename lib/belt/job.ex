defmodule Belt.Job do
  @moduledoc """
  A mechanism for maintaining state across the Belt processing chain.

  `Belt.Job` is implemented on top of `GenServer` and serves as a backchannel
  for Belt’s GenStage-based one-directional architecture.

  Newly created Jobs are automatically supervised by `Belt.Job.Supervisor`
  which is started as part of the Belt application.

  ## Usage:
  ```
  {:ok, job} = Belt.Job.new(:some_payload)
  Belt.Job.finished?(job)
  #=> false
  Belt.Job.finish(job, :some_reply)
  #=> :ok
  Belt.Job.finished?(job)
  #=> true
  {:ok, reply} = Belt.Job.await_and_shutdown(job)
  #=> {:ok, :some_reply}

  Belt.Job.new(:some_payload)
  |> Belt.Job.await_and_shutdown()
  #=> :timeout
  ```
  """

  use GenServer

  @timeout Belt.Config.timeout()

  @typedoc "The Job name"
  @type name :: {:via, module, term}

  @typedoc "The Job reference"
  @type t :: pid | name

  defstruct(
    payload: nil,
    reply: nil,
    finished?: false,
    subscribers: MapSet.new(),
    workers: MapSet.new()
  )


  @doc """
  Creates a new Job.

  If `name` is provided, the given term will be used for registering the new
  Job in `Belt.Job.Registry`.
  By default, or when `:auto` is passed as `name`, a unique name is
  automatically generated.

  Newly created Jobs will be supervised by `Belt.Job.Supervisor` using a
  `:transient` restart strategy.
  """
  @spec new(term, :auto | term) :: {:ok, t}
  def new(payload, name \\ :auto) do
    Belt.Job.Supervisor.start_child(payload, name)
  end


  @doc """
  Marks the given `job` as finished and stores `reply` as the result of the Job.

  All subscribers are sent the `:job_finished` message.

  `Belt.Job.finish/2` does not terminate the Job process. This can be done via `Belt.Job.shutdown/1`.
  """
  @spec finish(t | term, term) :: :ok | {:error, term}
  def finish(job, reply) do
    job
    |> get_job()
    |> GenServer.call({:finish, reply})
  end


  @doc """
  Returns the payload of the given `job`.
  """
  @spec get_payload(t | term) :: term
  def get_payload(job) do
    job
    |> get_job()
    |> GenServer.call({:get_payload})
  end


  @doc """
  Subscribes current process to `job` (using `self/0`) and waits for `timeout`
  milliseconds for its completion.

  `:infinity` can be passed for `timeout` if no timeout is desired.

  If a matching `:job_finished` message is received before the timeout expires,
  returns `{:ok, reply}`. Otherwise, returns `:timeout`.

  `await/2` doesn’t terminate the given `job`. This can be achieved by using
  `Belt.await/2`, `Belt.Job.await_and_shutdown/2` or `Belt.Job.shutdown/1`
  instead.
  """
  @spec await(t | term, integer | :infinity) :: {:ok, term} | :timeout
  def await(job, timeout \\ @timeout) do
    job = get_job(job)

    if (finished?(job)) do
      get_reply(job)
    else
      subscribe(job, self())
      pid = get_pid(job)
      receive do
        {:job_finished, ^pid, reply} -> {:ok, reply}
        after timeout -> :timeout
      end
    end
  end


  @doc """
  Subscribes current process to `job` (using `self/0`) and waits for `timeout`
  milliseconds for its completion.

  `:infinity` can be passed for `timeout` if no timeout is desired.

  If a matching `:job_finished` message is received before the timeout expires,
  returns `{:ok, reply}`. Otherwise, returns `:timeout`.

  The given Job process is shut down after a matching `:job_finished message`
  has been received or `timeout` has expired.
  """
  @spec await_and_shutdown(t | term, integer | :infinity) :: {:ok, term} | :timeout
  def await_and_shutdown(job, timeout \\ @timeout) do
    job = get_job(job)
    reply = await(job, timeout)
    shutdown(job)
    reply
  end


  @doc """
  Checks if the given `job` has been completed.
  """
  @spec finished?(t | term) :: true | false
  def finished?(job) do
    job
    |> get_job()
    |> GenServer.call({:finished?})
  end


  @doc """
  Checks if the given `job` is still running.
  """
  @spec alive?(t | term) :: true | false
  def alive?(job) do
    job
    |> get_job()
    |> GenServer.whereis()
    |> case do
      nil -> false
      _other -> true
    end
  end


  @doc """
  Terminates the given `job`.
  """
  @spec shutdown(t | term) :: :ok
  def shutdown(job) do
    job
    |> get_job()
    |> GenServer.stop()
  end


  @doc """
  Subscribes a `pid` to messages from the given `job`.
  """
  @spec subscribe(t | term, pid) :: :ok
  def subscribe(job, pid) do
    job
    |> get_job()
    |> GenServer.call({:subscribe, pid})
  end

  @doc """
  Registers a worker process with a given `job`.
  Workers get sent an `:exit` signal if they are still alive when the Job
  terminates.
  """
  @spec register_worker(t | term, pid) :: :ok
  def register_worker(job, pid) do
    job
    |> get_job()
    |> GenServer.call({:register_worker, pid})
  end


  @spec get_job(t | term) :: t
  defp get_job(job) when is_pid(job), do: job

  defp get_job({:via, _, _} = via_tuple), do: via_tuple

  defp get_job(job),
    do: {:via, Registry, {Belt.Job.Registry, job}}


  @spec get_pid(t) :: pid | {:error, term}
  defp get_pid(job) when is_pid(job), do: {:ok, job}

  defp get_pid({:via, Registry, {registry, name}}) do
    with [{pid, _}] <- Registry.lookup(registry, name) do
      pid
    else
      other -> {:error, "Could not find Job #{name}. Registry lookup returned #{inspect other}"}
    end
  end

  defp get_reply(pid) do
    GenServer.call(pid, {:get_reply})
  end


  defp broadcast(processes, message) do
    processes = processes
      |> MapSet.to_list()
    for process <- processes do
      Process.send(process, message, [])
    end
  end


  @doc false
  def start_link(name, payload) do
    opts = [name: {:via, Registry, {Belt.Job.Registry, name}}]
    GenServer.start_link(__MODULE__, payload, opts)
  end

  @doc false
  def init(payload) do
    state = %Belt.Job{payload: payload}
    {:ok, state}
  end

  @doc false
  def handle_call({:subscribe, pid}, _from, state) do
    subscribers = state.subscribers
      |> MapSet.put(pid)
    {:reply, :ok, %{state | subscribers: subscribers}}
  end

  @doc false
  def handle_call({:register_worker, pid}, _from, state) do
    workers = state.workers
      |> MapSet.put(pid)
    {:reply, :ok, %{state | workers: workers}}
  end

  @doc false
  def handle_call({:finish, reply}, _from, %{finished?: false} = state) do
    state = %{state | finished?: true, reply: reply}
    broadcast(state.subscribers, {:job_finished, self(), reply})
    {:reply, :ok, state}
  end

  @doc false
  def handle_call({:get_payload}, _from, %{payload: payload} = state) do
    {:reply, payload, state}
  end

  @doc false
  def handle_call({:finished?}, _from, %{finished?: finished?} = state),
    do: {:reply, finished?, state}

  @doc false
  def handle_call({:get_reply}, _from, %{reply: reply, finished?: finished?} = state) do
    reply = case finished? do
      true -> {:ok, reply}
      _ -> :error
    end
    {:reply, reply, state}
  end

  @doc false
  def terminate(_reason, state) do
    broadcast(state.subscribers, {:job_terminated, self()})
    workers = state.workers
      |> MapSet.to_list()
    for worker <- workers do
      Process.exit(worker, :normal)
    end
  end
end

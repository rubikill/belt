defmodule Belt.Test.Job do
  use ExUnit.Case
  doctest Belt.Job

  defp create_and_finish_job(name, payload, reply, finish_delay) do
    {:ok, name} = Belt.Job.new(payload, name)
    [{pid, _}] = Registry.lookup(Belt.Job.Registry, name)
    Task.async(fn ->
      :timer.sleep(finish_delay)
      Belt.Job.finish(name, reply)
    end)
    {name, pid}
  end

  test "create and shutdown an unnamed Job" do
    {:ok, name} = Belt.Job.new(nil)
    [{pid, _}] = Registry.lookup(Belt.Job.Registry, name)
    assert is_pid(pid)
    assert Process.alive?(pid)
    Belt.Job.shutdown(name)
    refute Process.alive?(pid)
  end

  test "create a named Job" do
    name = "foo"
    {:ok, ^name} = Belt.Job.new(nil, name)
    [{pid, _}] = Registry.lookup(Belt.Job.Registry, name)
    assert is_pid(pid)
    assert Process.alive?(pid)
  end

  test "store the payload" do
    payload = "foo"
    {:ok, name} = Belt.Job.new(payload)
    assert payload == Belt.Job.get_payload(name)
  end

  test "await and shutdown" do
    reply = "foo"

    {name, pid} = create_and_finish_job(:auto, nil, reply, 100)
    assert {:ok, reply} == Belt.Job.await_and_shutdown(name)
    refute Process.alive?(pid)

    {name, pid} = create_and_finish_job(:auto, nil, reply, 1000)
    assert :timeout = Belt.Job.await_and_shutdown(name, 0)
    refute Process.alive?(pid)
  end

  test "finish before await" do
    reply = "foo"

    {:ok, job} = Belt.Job.new(nil)
    Belt.Job.finish(job, reply)
    assert {:ok, reply} == Belt.Job.await(job)
  end

  test "finish after await" do
    reply = "foo"

    {job, _pid} = create_and_finish_job(:auto, nil, reply, 1000)
    assert {:ok, reply} == Belt.Job.await(job)
  end

  test "await timeout" do
    reply = "foo"
    {job, _pid} = create_and_finish_job(:auto, nil, reply, 1000)
    assert :timeout == Belt.Job.await(job, 0)
  end

  test "Job stays alive after await/2" do
    reply = "foo"

    {job, pid} = create_and_finish_job(:auto, nil, reply, 100)
    Belt.Job.await(job, 1000)
    assert Process.alive?(pid)

    #With timeout
    {job, _pid} = create_and_finish_job(:auto, nil, reply, 1000)
    Belt.Job.await(job, 100)
    assert Process.alive?(pid)
  end
end

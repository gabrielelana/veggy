defmodule Veggy.Registry do
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def dispatch(%{command: _} = command) do
    GenServer.cast(__MODULE__, {:dispatch, command})
  end

  def handle_cast({:dispatch, %{aggregate_id: id, aggregate_kind: kind} = command}, registry) do
    IO.inspect({:dispatch, command, :in, registry})
    result = Map.get_and_update(registry, id, &spawn_aggregate(&1, id, kind))
    IO.inspect(result)
    {pid, registry} = result
    IO.inspect("Ask aggregate with pid #{inspect(pid)} to handle command")
    Veggy.Aggregate.handle(pid, command)
    {:noreply, registry}
  end

  # TODO: handle the death of the aggregate process
  defp spawn_aggregate(pid, _, _) when is_pid(pid), do: {pid, pid}
  defp spawn_aggregate(nil, id, kind) do
    {:ok, pid} = Veggy.Aggregate.start_link(id, kind)
    {pid, pid}
  end
end

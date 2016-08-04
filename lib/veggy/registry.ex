defmodule Veggy.Registry do
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def dispatch(request, module) do
    # TODO: how to ensure that a module implements a behaviour?
    {:ok, command} = module.route(request)
    GenServer.cast(__MODULE__, {:dispatch, command, module})
    {:ok, command}
  end

  def handle_cast({:dispatch, command, module}, registry) do
    # TODO: how to ensure that a module implements a behaviour?
    {pid, registry} = aggregate_for(registry, command)
    Veggy.Aggregate.handle(pid, command)
    {:noreply, registry}
  end

  defp aggregate_for(registry, %{aggregate_id: id, aggregate_module: module}) do
    Map.get_and_update(registry, id, &spawn_aggregate(&1, id, module))
  end

  # TODO: handle the death of the aggregate process
  defp spawn_aggregate(pid, _, _) when is_pid(pid), do: {pid, pid}
  defp spawn_aggregate(nil, id, module) do
    {:ok, pid} = Veggy.Aggregate.start_link(id, module)
    {pid, pid}
  end
end

defmodule Veggy.Aggregates do
  use GenServer

  def start_link(modules) do
    GenServer.start_link(__MODULE__, %{modules: modules, registry: %{}}, name: __MODULE__)
  end

  def dispatch(request) do
    case GenServer.call(__MODULE__, {:route, request}) do
      {:ok, command} ->
        GenServer.cast(__MODULE__, {:dispatch, command})
        {:ok, command}
      {:error, _} = error ->
        error
    end
  end

  def handle_call({:route, request}, _from, %{modules: modules} = state) do
    command = Enum.find_value(modules, {:error, :unknown_command}, &(&1.route(request)))
    {:reply, command, state}
  end

  def handle_cast({:dispatch, command}, %{registry: registry} = state) do
    # TODO: how to ensure that a module implements a behaviour?
    {pid, registry} = aggregate_for(registry, command)
    Veggy.Aggregate.handle(pid, command)
    {:noreply, %{state | registry: registry}}
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
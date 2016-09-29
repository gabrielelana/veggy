defmodule Veggy.Projections do
  use GenServer

  def start_link(modules) do
    # TODO: start projections asynchronously
    registry = Enum.reduce(modules, %{}, fn(module, registry) ->
      {:ok, pid} = Veggy.Projection.start_link(module)
      Map.put(registry, module, pid)
    end)

    GenServer.start_link(__MODULE__, %{modules: modules, registry: registry}, name: __MODULE__)
  end

  def dispatch(%Plug.Conn{} = conn, projection_name) do
    GenServer.call(__MODULE__, {:query, projection_name, conn.params})
  end

  def handle_call({:query, projection_name, parameters}, _from, %{modules: modules} = state) do
    # TODO: catch function clause error
    result = Enum.find_value(modules, {:not_found, :projection}, &(&1.query(projection_name, parameters)))
    {:reply, result, state}
  end
end

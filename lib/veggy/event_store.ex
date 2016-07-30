defmodule Veggy.EventStore do
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def emit(%{event: _} = event) do
    IO.inspect({:emit, event})
    GenServer.cast(__MODULE__, {:emit, event})
  end

  def handle_cast({:emit, event}, state) do
    IO.inspect({:received, event})
    {:noreply, state}
  end
end

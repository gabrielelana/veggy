defmodule Veggy.EventStore do
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def emit(%{event: _} = event) do
    GenServer.cast(__MODULE__, {:event, event})
  end

  def subscribe(pid, check) do
    reference = make_ref
    GenServer.cast(__MODULE__, {:subscribe, reference, check, pid})
    reference
  end

  def unsubscribe(reference) do
    GenServer.cast(__MODULE__, {:unsubscribe, reference})
  end

  def handle_cast({:event, event}, state) do
    event = Map.put(event, :received_at, DateTime.utc_now)
    # IO.inspect({:received, event})
    Enum.each(state, fn({_, {check, pid}}) ->
      if check.(event), do: send(pid, {:event, event})
    end)
    {:noreply, state}
  end
  def handle_cast({:subscribe, reference, check, pid}, state) do
    {:noreply, Map.put(state, reference, {check, pid})}
  end
  def handle_cast({:unsubscribe, reference}, state) do
    {:noreply, Map.delete(state, reference)}
  end
end

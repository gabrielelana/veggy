defmodule Veggy.Projection do
  use GenServer

  def start_link(module) do
    GenServer.start_link(__MODULE__, %{module: module})
  end

  def init(state) do
    state.module.init
    {:ok, state}
  end

  def handle_info({:event, event}, state) do
    # IO.inspect({:received, event})
    record = state.module.fetch(event)
    # IO.inspect({:fetched, record})
    record = state.module.process(event, record)
    # IO.inspect({:processed, record})
    state.module.store(record)
    # TODO: remember where we arrived at processing events
    {:noreply, state}
  end
end

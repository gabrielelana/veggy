defmodule Veggy.Projection do
  use GenServer

  def start_link(module) do
    GenServer.start_link(__MODULE__, %{module: module})
  end

  def init(%{module: module}) do
    module.init
    {:ok, %{module: module}}
  end

  def handle_info({:event, event}, state) do
    record = state.module.fetch(event)
    case state.module.process(event, record) do
      :skip -> raise "unimplemented"
      :hold -> raise "unimplemented"
      :delete -> state.module.delete(record)
      {:error, _reason} -> raise "unimplemented"
      record -> state.module.store(record)
    end
    {:noreply, state}
  end
end

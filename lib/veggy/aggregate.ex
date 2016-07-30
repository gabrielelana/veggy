defmodule Veggy.Aggregate do
  use GenServer

  def start_link(id, kind) do
    behaviour = Module.concat(Veggy.Aggregate, kind)
    # TODO: check it implements the behaviour
    IO.inspect("Start aggregate process with #{behaviour} behaviour")
    GenServer.start_link(__MODULE__, %{id: id, module: behaviour, aggregate: nil})
  end

  def handle(pid, %{command: _} = command) do
    IO.inspect("Asked to handle command with behaviour")
    GenServer.cast(pid, command)
  end

  def handle_cast(%{command: _} = command, %{aggregate: nil} = state) do
    handle_cast(command, %{state | aggregate: state.module.fetch(state.id)})
  end
  def handle_cast(%{command: _} = command, state) do
    IO.inspect({:before, command, state.aggregate})
    events = case state.module.handle(command, state.aggregate) do
               {:ok, event} -> [event, succeded(command)]
               {:error, reason} -> [failed(command, reason)]
             end
    IO.inspect({:events, events})
    aggregate = Enum.reduce(events, state.aggregate, &state.module.on/2)
    IO.inspect({:after, command, aggregate})
    # TODO: send events to event store
    {:noreply, %{state | aggregate: aggregate}}
  end

  defp succeded(%{command: _} = command) do
    %{event: "CommandSucceeded", command_id: command.id}
  end

  defp failed(%{command: _} = command, reason) do
    %{event: "CommandFailed", command_id: command.id, why: reason}
  end
end

defmodule Veggy.Aggregate do
  use GenServer
  # TODO: define callbacks for Aggregate behaviour

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
    aggregate = state.module.init(state.id)
    aggregate = state.module.fetch(state.id, aggregate)
    handle_cast(command, %{state | aggregate: aggregate})
  end
  def handle_cast(%{command: _} = command, state) do
    IO.inspect({:before, command, state.aggregate})
    Veggy.EventStore.emit(received(command))
    events = case state.module.handle(command, state.aggregate) do
               {:ok, event} -> [event, succeded(command)]
               {:error, reason} -> [failed(command, reason)]
             end
    IO.inspect({:events, events})
    aggregate = Enum.reduce(events, state.aggregate, &state.module.on/2)
    IO.inspect({:after, command, aggregate})
    Enum.each(events, &Veggy.EventStore.emit/1)
    {:noreply, %{state | aggregate: aggregate}}
  end

  def handle_info({:event, event}, state) do
    IO.inspect({:before, event, state.aggregate})
    aggregate = state.module.on(event, state.aggregate)
    IO.inspect({:after, event, aggregate})
    {:noreply, %{state | aggregate: aggregate}}
  end

  defp received(%{command: _} = command),
    do: %{event: "CommandReceived", command_id: command.id, id: Veggy.UUID.new}

  defp succeded(%{command: _} = command),
    do: %{event: "CommandSucceeded", command_id: command.id, id: Veggy.UUID.new}

  defp failed(%{command: _} = command, reason),
    do: %{event: "CommandFailed", command_id: command.id, why: reason, id: Veggy.UUID.new}
end

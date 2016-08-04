defmodule Veggy.Aggregate do
  use GenServer

  # @type command :: Map.t
  # @type event :: Map.t

  # @callback route(request::any) ::
  #   {:ok, command} |
  #   {:error, reason::any} |
  #   :unknown

  # @callback init(id::any) ::
  #   {:ok, default_state::any} |
  #   {:error, reason::any}

  # @callback fetch(id::any, default_state::any) ::
  #   {:ok, state::any} |
  #   {:error, reason::any}

  # @callback handle(command, state::any) ::
  #   {:ok, [event]} |
  #   {:ok, [event], [command]} |
  #   {:forward, command} |
  #   {:fork, [command]}

  # @callback process(event, state::any) ::
  #   state::any

  def start_link(id, module) do
    GenServer.start_link(__MODULE__, %{id: id, module: module, aggregate: nil})
  end

  def handle(pid, %{command: _} = command) do
    GenServer.cast(pid, command)
  end

  def handle_cast(%{command: _} = command, %{aggregate: nil} = state),
    do: handle_cast(command, %{state | aggregate: do_init(state)})
  def handle_cast(%{command: _} = command, state) do
    Veggy.EventStore.emit(received(command))
    events = case state.module.handle(command, state.aggregate) do
               {:ok, event} -> [event, succeded(command)]
               {:error, reason} -> [failed(command, reason)]
             end
    aggregate = Enum.reduce(events, state.aggregate, &state.module.process/2)
    state.module.store(aggregate)
    Enum.each(events, &Veggy.EventStore.emit/1)
    {:noreply, %{state | aggregate: aggregate}}
  end

  def handle_info({:event, _} = event, %{aggregate: nil} = state),
    do: handle_info(event, %{state | aggregate: do_init(state)})
  def handle_info({:event, event}, state) do
    aggregate = state.module.process(event, state.aggregate)
    state.module.store(aggregate)
    {:noreply, %{state | aggregate: aggregate}}
  end

  defp do_init(state) do
    aggregate = state.module.init(state.id)
    aggregate = state.module.fetch(state.id, aggregate)
  end

  defp received(%{command: _} = command),
    do: %{event: "CommandReceived", command_id: command.id, id: Veggy.UUID.new}

  defp succeded(%{command: _} = command),
    do: %{event: "CommandSucceeded", command_id: command.id, id: Veggy.UUID.new}

  defp failed(%{command: _} = command, reason),
    do: %{event: "CommandFailed", command_id: command.id, why: reason, id: Veggy.UUID.new}
end

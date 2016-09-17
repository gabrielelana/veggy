defmodule Veggy.Aggregate do
  use GenServer

  # @type command :: Map.t
  # @type event :: Map.t
  # @type related_events :: event | [event]
  # @type related_commands ::
  #   command |
  #   [command] |
  #   {:forward, command} |
  #   {:chain, [command]} |
  #   {:fork, [command]}

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
  #   {:ok, related_events} |
  #   {:ok, related_events, related_commands} |
  #   {:error, reason::any} |
  #   {:error, reason::any, [events]} |
  #   {:error, reason::any, [events], [commands]}

  # @callback rollback(command, state::any) ::
  #   {:ok, related_events} |
  #   {:error, reason::any}

  # @callback process(event, state::any) ::
  #   state::any

  def start_link(id, module) do
    GenServer.start_link(__MODULE__, %{id: id, module: module, aggregate: nil})
  end

  def handle(pid, %{"command" => _} = command) do
    GenServer.cast(pid, {:handle, command})
  end
  def rollback(pid, %{"command" => _} = command) do
    GenServer.cast(pid, {:rollback, command})
  end


  def handle_cast({op, %{"command" => _} = command}, %{aggregate: nil} = state),
    do: handle_cast({op, command}, %{state | aggregate: do_init(state)})

  def handle_cast({:handle, %{"command" => _} = command}, state) do
    Veggy.EventStore.emit(received(command))

    {outcome_event, emitted_events, related_commands} =
      handle_command(command, state.module, state.aggregate)

    # TODO: ensure every commands has what we need otherwise blow up and explain why
    # TODO: ensure every events has what we need otherwise blow up and explain why
    # TODO: enrich emitted_events with: command id and other correlation ids known by the aggregate
    #       should every aggregate have a special storage for correlation ids?

    outcome_event = correlate_outcome(outcome_event, emitted_events, related_commands)
    route_commands(command, related_commands)
    aggregate_state = process_events(emitted_events, state.module, state.aggregate)

    # XXX: here we have a potential inconsistency, if this process dies here
    # we have changed the aggregate state but we have not yet emitted the events
    # so the state of the aggregate is inconsistent with the emitted events.
    # We should consider to not store the aggregate state at all but to
    # regenerate it from all its events when spawned

    commit_events([outcome_event | emitted_events])

    {:noreply, %{state | aggregate: aggregate_state}}
  end

  def handle_cast({:rollback, %{"command" => _} = command}, state) do
    {outcome_event, emitted_events} =
      rollback_command(command, state.module, state.aggregate)

    # TODO: ensure every events has what we need otherwise blow up and explain why
    # TODO: enrich emitted_events with: command id and other correlation ids known by the aggregate
    #       should every aggregate have a special storage for correlation ids?

    outcome_event = correlate_outcome(outcome_event, emitted_events, [])
    aggregate_state = process_events(emitted_events, state.module, state.aggregate)
    commit_events([outcome_event | emitted_events])
    {:noreply, %{state | aggregate: aggregate_state}}
  end

  def handle_info({:event, _} = event, %{aggregate: nil} = state),
    do: handle_info(event, %{state | aggregate: do_init(state)})
  def handle_info({:event, event}, state) do
    aggregate_state = process_events([event], state.module, state.aggregate)
    {:noreply, %{state | aggregate: aggregate_state}}
  end

  def terminate(_, _) do
    :ok
  end


  def handle_command(command, aggregate_module, aggregate_state) do
    case aggregate_module.handle(command, aggregate_state) do
      {:ok, event} when is_map(event) -> {succeeded(command), [event], []}
      {:ok, events} when is_list(events) -> {succeeded(command), events, []}
      {:ok, events, {_, _} = commands} -> {splitted(command), events, commands}
      {:ok, events, commands} -> {succeeded(command), events, commands}
      {:error, reason} -> {failed(command, reason), [], []}
      {:error, reason, events} -> {failed(command, reason), events, []}
      {:error, reason, events, commands} -> {failed(command, reason), events, commands}
      # TODO: blow up but before explain what we are expecting
    end
  end

  def rollback_command(command, aggregate_module, aggregate_state) do
    case aggregate_module.rollback(command, aggregate_state) do
      {:ok, event} when is_map(event) -> {rolledback(command), [event]}
      {:ok, events} when is_list(events) -> {rolledback(command), events}
      {:error, reason} -> raise reason # TODO: do something better
      # TODO: blow up but before explain what we are expecting
    end
  end

  def correlate_outcome(outcome, events, {_, commands}),
    do: correlate_outcome(outcome, events, commands)
  def correlate_outcome(outcome, events, commands) do
    outcome
    |> Map.put("events", Enum.map(events, &Map.get(&1, "id")))
    |> Map.put("commands", Enum.map(commands, &Map.get(&1, "id")))
  end

  def route_commands(parent, {:fork, commands}), do: Veggy.Transaction.ForkAndJoin.start(parent, commands)
  # def route_commands(parent, {:chain, commands}), do: Veggy.Transaction.Chain.start(parent, commands)
  # def route_commands(parent, {:forward, command}), do: Veggy.Transaction.Forward.start(parent, command)
  def route_commands(_parent, commands) do
    # TODO: Veggy.Transaction.FireAndForget.start(parent, commands)
    Enum.each(commands, &Veggy.Aggregates.dispatch/1)
  end

  def process_events(events, aggregate_module, aggregate_state) do
    aggregate_state = Enum.reduce(events, aggregate_state, &aggregate_module.process/2)
    aggregate_module.store(aggregate_state)
    aggregate_state
  end

  def commit_events(events) do
    Enum.each(events, &Veggy.EventStore.emit/1)
  end


  defp do_init(state) do
    aggregate = state.module.init(state.id)
    aggregate = state.module.fetch(state.id, aggregate)
    aggregate
  end

  defp received(%{"command" => _, "id" => id} = command),
    do: %{"event" => "CommandReceived", "command_id" => id, "command" => command, "id" => Veggy.UUID.new}

  defp succeeded(%{"id" => id}),
    do: %{"event" => "CommandSucceeded", "command_id" => id, "id" => Veggy.UUID.new}

  defp splitted(%{"id" => id}),
    do: %{"event" => "CommandSplitted", "command_id" => id, "id" => Veggy.UUID.new}

  defp failed(%{"id" => id}, reason),
    do: %{"event" => "CommandFailed", "command_id" => id, "why" => reason, "id" => Veggy.UUID.new}

  defp rolledback(%{"id" => id}),
    do: %{"event" => "CommandRolledBack", "command_id" => id, "id" => Veggy.UUID.new}
end

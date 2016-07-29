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

defmodule Veggy.Aggregate.Timer do
  # TODO: @behaviour Veggy.Aggregate
  # TODO: use Veggy.Mongo.Aggregate, collection: "timer"

  def fetch(id) do
    %{id: id, ticking: false}
  end

  def store(_state) do
    :ok
  end

  def handle(%{command: "StartPomodoro"}, %{ticking: true}), do: {:error, "Pomodoro is ticking"}
  def handle(%{command: "StartPomodoro"}, _) do
    # TODO: start timer for 25 minutes
    # TODO: populate event with what is needed
    {:ok, %{event: "PomodoroStarted"}}
  end

  def on(%{event: "PomodoroStarted"}, s), do: %{s | ticking: true}
  def on(%{event: "PomodoroEnded"}, s), do: %{s | ticking: false}
  def on(_, s), do: s
end

defmodule Veggy.Registry do
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def dispatch(%{command: _} = command) do
    GenServer.cast(__MODULE__, {:dispatch, command})
  end

  def handle_cast({:dispatch, %{aggregate_id: id, aggregate_kind: kind} = command}, registry) do
    IO.inspect({:dispatch, command, :in, registry})
    result = Map.get_and_update(registry, id, &spawn_aggregate(&1, id, kind))
    IO.inspect(result)
    {pid, registry} = result
    IO.inspect("Ask aggregate with pid #{inspect(pid)} to handle command")
    Veggy.Aggregate.handle(pid, command)
    {:noreply, registry}
  end

  # TODO: handle the death of the aggregate process
  defp spawn_aggregate(pid, _, _) when is_pid(pid), do: {pid, pid}
  defp spawn_aggregate(nil, id, kind) do
    {:ok, pid} = Veggy.Aggregate.start_link(id, kind)
    {pid, pid}
  end
end

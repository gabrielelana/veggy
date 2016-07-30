defmodule Veggy.Aggregate.Timer do
  # TODO: @behaviour Veggy.Aggregate
  # TODO: use Veggy.Mongo.Aggregate, collection: "timer"

  def init(id) do
    Veggy.EventStore.subscribe(self, &match?(%{event: "PomodoroEnded", aggregate_id: id}, &1))
    []
  end

  def fetch(id, _) do
    %{id: id, ticking: false}
  end

  def store(_aggregate) do
    :ok
  end

  def handle(%{command: "StartPomodoro"}, %{ticking: true}), do: {:error, "Pomodoro is ticking"}
  def handle(%{command: "StartPomodoro"} = command, aggregate) do
    {:ok, pomodoro_id} = Veggy.Timers.start(command.duration, aggregate.id)
    {:ok, %{event: "PomodoroStarted",
            pomodoro_id: pomodoro_id,
            command_id: command.id,
            aggregate_id: aggregate.id,
            duration: command.duration,
            id: Mongo.IdServer.new}}
  end

  def on(%{event: "PomodoroStarted"}, s), do: %{s | ticking: true}
  def on(%{event: "PomodoroEnded"}, s), do: %{s | ticking: false}
  def on(_, s), do: s
end

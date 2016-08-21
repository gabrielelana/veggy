defmodule Veggy.Aggregate.Timer do
  # @behaviour Veggy.Aggregate
  use Veggy.MongoDB.Aggregate, collection: "aggregate.timers"

  def route(%Plug.Conn{params: %{"command" => "StartPomodoro"} = params}) do
    {:ok, %{command: "StartPomodoro",
            aggregate_id: params["timer_id"],
            aggregate_module: __MODULE__,
            duration: Map.get(params, "duration", 25*60*1000),
            id: Veggy.UUID.new}}
  end
  def route(_), do: nil

  def init(id) do
    Veggy.EventStore.subscribe(self, &match?(%{event: "PomodoroEnded", aggregate_id: ^id}, &1))
    %{"id" => id, "ticking" => false}
  end

  def handle(%{command: "StartPomodoro"}, %{"ticking" => true}), do: {:error, "Pomodoro is ticking"}
  def handle(%{command: "StartPomodoro"} = command, aggregate) do
    {:ok, pomodoro_id} = Veggy.Countdown.start(command.duration, aggregate["id"])
    {:ok, %{event: "PomodoroStarted",
            pomodoro_id: pomodoro_id,
            command_id: command.id,
            aggregate_id: aggregate["id"],
            duration: command.duration,
            id: Veggy.UUID.new}}
  end

  def process(%{event: "PomodoroStarted"}, s), do: %{s | "ticking" => true}
  def process(%{event: "PomodoroEnded"}, s), do: %{s | "ticking" => false}
  def process(_, s), do: s
end

defmodule Veggy.Aggregate.Timer do
  use Veggy.Aggregate
  use Veggy.MongoDB.Aggregate, collection: "aggregate.timers"

  @default_duration 1_500_000   # 25 minutes in milliseconds

  def route(%{"command" => "StartPomodoro"} = p) do
    {:ok, command("StartPomodoro", "timer",
        duration: Map.get(p, "duration", @default_duration),
        description: Map.get(p, "description", ""))}
  end
  def route(%{"command" => "SquashPomodoro"} = p) do
    {:ok, command("SquashPomodoro", "timer",
        reason: Map.get(p, "reason", ""))}
  end

  def init(id) do
    Veggy.EventStore.subscribe(self, &match?(%{"event" => "PomodoroCompleted", "aggregate_id" => ^id}, &1))
    {:ok, %{"id" => id, "ticking" => false}}
  end

  def handle(%{"command" => "StartPomodoro"}, %{"ticking" => true}), do: {:error, "Pomodoro is ticking"}
  def handle(%{"command" => "StartPomodoro"} = c, s) do
    {:ok, pomodoro_id} = Veggy.Countdown.start(c["duration"], s["id"], c["_id"])
    {:ok, event("PomodoroStarted",
        pomodoro_id: pomodoro_id,
        duration: c["duration"],
        description: c["description"])}
  end
  def handle(%{"command" => "SquashPomodoro"}, %{"ticking" => false}), do: {:error, "Pomodoro is not ticking"}
  def handle(%{"command" => "SquashPomodoro"} = c, %{"pomodoro_id" => pomodoro_id}) do
    :ok = Veggy.Countdown.squash(pomodoro_id)
    {:ok, event("PomodoroSquashed",
        reason: c["reason"])}
  end

  def process(%{"event" => "PomodoroStarted", "pomodoro_id" => pomodoro_id}, s),
    do: %{s | "ticking" => true} |> Map.put("pomodoro_id", pomodoro_id)
  def process(%{"event" => "PomodoroSquashed"}, s),
    do: %{s | "ticking" => false} |> Map.delete("pomodoro_id")
  def process(%{"event" => "PomodoroCompleted"}, s),
    do: %{s | "ticking" => false} |> Map.delete("pomodoro_id")
end

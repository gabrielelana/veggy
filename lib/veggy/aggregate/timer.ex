defmodule Veggy.Aggregate.Timer do
  use Veggy.Aggregate
  use Veggy.MongoDB.Aggregate, collection: "aggregate.timers"
  use Testable

  @default_duration 1_500_000   # 25 minutes in milliseconds

  defp aggregate_id(%{"timer_id" => timer_id}),
    do: Veggy.MongoDB.ObjectId.from_string(timer_id)

  def route(%{"command" => "StartPomodoro"} = p) do
    {:ok, command("StartPomodoro", aggregate_id(p),
        duration: Map.get(p, "duration", @default_duration),
        description: Map.get(p, "description", ""),
        shared_with: Map.get(p, "shared_with", []) |> Enum.map(&Veggy.MongoDB.ObjectId.from_string/1))}
  end
  def route(%{"command" => "SquashPomodoro"} = p) do
    {:ok, command("SquashPomodoro", aggregate_id(p),
        reason: Map.get(p, "reason", ""))}
  end
  def route(%{"command" => "StartSharedPomodoro"} = p) do
    {:ok, command("StartSharedPomodoro", aggregate_id(p),
        duration: Map.get(p, "duration", @default_duration),
        description: Map.get(p, "description", ""),
        shared_with: Map.get(p, "shared_with", []) |> Enum.map(&Veggy.MongoDB.ObjectId.from_string/1))}
  end
  def route(%{"command" => "SquashSharedPomodoro"} = p) do
    {:ok, command("SquashSharedPomodoro", aggregate_id(p),
        reason: Map.get(p, "reason", ""))}
  end
  def route(%{"command" => "TrackPomodoroCompleted"} = p) do
    route_track(p, "completed_at")
  end
  def route(%{"command" => "TrackPomodoroSquashed"} = p) do
    route_track(p, "squashed_at")
  end

  defp route_track(p, ended_field) do
    with {:ok, started_at} <- Timex.parse(p["started_at"], "{RFC3339z}"),
         {:ok, ended_at} <- Timex.parse(p[ended_field], "{RFC3339z}") do
      {:ok, command(p["command"], aggregate_id(p),
          [started_at: started_at,
           duration: Timex.diff(ended_at, started_at, :milliseconds),
           description: Map.get(p, "description", "")]
          |> Keyword.put(String.to_atom(ended_field), ended_at))}
    else
      _ ->
        {:error, "Wrong time format"}
    end
  end

  def init(id) do
    Veggy.EventStore.subscribe(self, &match?(%{"event" => "PomodoroCompleted", "aggregate_id" => ^id}, &1))
    {:ok, %{"id" => id, "ticking" => false}}
  end

  def handle(%{"command" => "CreateTimer", "user_id" => user_id}, _) do
    {:ok, event("TimerCreated", user_id: user_id)}
  end
  def handle(%{"command" => "StartPomodoro"}, %{"ticking" => true}), do: {:error, "Pomodoro is ticking"}
  def handle(%{"command" => "StartPomodoro"} = c, s) do
    {:ok, pomodoro_id} = Veggy.Countdown.start(c["duration"], s["id"], s["user_id"], c["_id"])
    {:ok, event("PomodoroStarted",
        pomodoro_id: pomodoro_id,
        duration: c["duration"],
        description: c["description"],
        shared_with: c["shared_with"])}
  end
  def handle(%{"command" => "SquashPomodoro"}, %{"ticking" => false}), do: {:error, "Pomodoro is not ticking"}
  def handle(%{"command" => "SquashPomodoro"} = c, %{"pomodoro_id" => pomodoro_id}) do
    :ok = Veggy.Countdown.squash(pomodoro_id)
    {:ok, event("PomodoroSquashed",
        reason: c["reason"])}
  end
  def handle(%{"command" => "StartSharedPomodoro", "shared_with" => shared_with} = c, s) do
    pairs = [s["id"] | shared_with]
    commands = Enum.map(pairs,
      fn(id) ->
        command("StartPomodoro", id,
          duration: c["duration"],
          description: c["description"],
          shared_with: pairs -- [id])
      end)
    {:ok, [], {:fork, commands}}
  end
  def handle(%{"command" => "SquashSharedPomodoro"} = c, %{"shared_with" => shared_with} = s) do
    pairs = [s["id"] | shared_with]
    commands = Enum.map(pairs,
      fn(id) ->
        command("SquashPomodoro", id,
          reason: c["reason"])
      end)
    {:ok, [], commands}
  end
  def handle(%{"command" => "TrackPomodoroCompleted"} = c, s) do
    handle_track(c, "completed_at", "PomodoroCompletedTracked", s["id"])
  end
  def handle(%{"command" => "TrackPomodoroSquashed"} = c, s) do
    handle_track(c, "squashed_at", "PomodoroSquashedTracked", s["id"])
  end

  defp handle_track(c, ended_field, event_name, aggregate_id) do
    if Timex.before?(c[ended_field], Timex.now) do

      events = Veggy.Projection.events_where(Veggy.Projection.Pomodori, {:aggregate_id, aggregate_id})
      pomodori = Veggy.Projection.process(Veggy.Projection.Pomodori, events)

      if compatible?(pomodori, c["started_at"], c[ended_field]) do
        {:ok, event(event_name,
            [started_at: c["started_at"],
             duration: c["duration"],
             description: c["description"]]
            |> Keyword.put(String.to_atom(ended_field), c[ended_field]))}
      else
        {:error, "Another pomodoro was ticking between #{c["started_at"]} and #{c[ended_field]}"}
      end
    else
      {:error, "Seems like you want to track a pomodoro that is not in the past... :-/"}
    end
  end

  defpt compatible?(pomodori, started_at, ended_at) do
    import Map, only: [put: 3, has_key?: 2]
    import Timex, only: [after?: 2, before?: 2]
    pomodori
    |> Enum.map(fn
      (%{"completed_at" => t} = p) -> put(p, "ended_at", t)
      (%{"squashed_at" => t} = p) -> put(p, "ended_at", t)
    end)
    |> Enum.filter(fn(p) -> has_key?(p, "started_at") && has_key?(p, "ended_at") end)
    |> Enum.map(fn(p) -> {p["started_at"], p["ended_at"]} end)
    |> Enum.all?(fn({t1, t2}) -> after?(started_at, t2) || before?(ended_at, t1) end)
  end

  def rollback(%{"command" => "StartPomodoro"}, %{"ticking" => false}), do: {:error, "No pomodoro to rollback"}
  def rollback(%{"command" => "StartPomodoro"}, %{"pomodoro_id" => pomodoro_id}) do
    :ok = Veggy.Countdown.void(pomodoro_id)
    {:ok, event("PomodoroVoided", [])}
  end

  def process(%{"event" => "TimerCreated", "user_id" => user_id}, s),
    do: Map.put(s, "user_id", user_id)
  def process(%{"event" => "PomodoroStarted"} = e, s),
    do: %{s | "ticking" => true} |> Map.merge(Map.take(e, ["pomodoro_id", "shared_with"]))
  def process(%{"event" => "PomodoroSquashed"}, s),
    do: %{s | "ticking" => false} |> Map.delete("pomodoro_id") |> Map.delete("shared_with")
  def process(%{"event" => "PomodoroCompleted"}, s),
    do: %{s | "ticking" => false} |> Map.delete("pomodoro_id") |> Map.delete("shared_with")
  def process(%{"event" => "PomodoroVoided"}, s),
    do: %{s | "ticking" => false} |> Map.delete("pomodoro_id") |> Map.delete("shared_with")
  def process(%{"event" => "PomodoroCompletedTracked"}, s),
    do: s
  def process(%{"event" => "PomodoroSquashedTracked"}, s),
    do: s
end

defmodule Veggy.Aggregate.Timer do
  @default_duration 1_500_000   # 25 minutes in milliseconds

  # @behaviour Veggy.Aggregate || use Veggy.Aggregate
  use Veggy.MongoDB.Aggregate, collection: "aggregate.timers"

  def route(%{"command" => "StartPomodoro"} = params) do
    {:ok, %{"command" => "StartPomodoro",
            "aggregate_id" => Veggy.MongoDB.ObjectId.from_string(params["timer_id"]),
            "aggregate_module" => __MODULE__,
            "duration" => Map.get(params, "duration", @default_duration),
            "description" => Map.get(params, "description", ""),
            "shared_with" => Map.get(params, "shared_with", []),
            "_id" => Veggy.UUID.new}}
  end
  def route(%{"command" => "SquashPomodoro"} = params) do
    {:ok, %{"command" => "SquashPomodoro",
            "aggregate_id" => Veggy.MongoDB.ObjectId.from_string(params["timer_id"]),
            "aggregate_module" => __MODULE__,
            "reason" => Map.get(params, "reason", ""),
            "_id" => Veggy.UUID.new}}
  end
  def route(%{"command" => "StartSharedPomodoro"} = params) do
    {:ok, %{"command" => "StartSharedPomodoro",
            "aggregate_id" => Veggy.MongoDB.ObjectId.from_string(params["timer_id"]),
            "aggregate_module" => __MODULE__,
            "duration" => Map.get(params, "duration", @default_duration),
            "description" => Map.get(params, "description", ""),
            "shared_with" => Map.get(params, "shared_with", []) |> Enum.map(&Veggy.MongoDB.ObjectId.from_string/1),
            "_id" => Veggy.UUID.new}}
  end
  def route(%{"command" => "SquashSharedPomodoro"} = params) do
    {:ok, %{"command" => "SquashSharedPomodoro",
            "aggregate_id" => Veggy.MongoDB.ObjectId.from_string(params["timer_id"]),
            "aggregate_module" => __MODULE__,
            "reason" => Map.get(params, "reason", ""),
            "_id" => Veggy.UUID.new}}
  end
  def route(%{"command" => "TrackPomodoroCompleted"} = params) do
    route_tracked(params, "completed_at")
  end
  def route(%{"command" => "TrackPomodoroSquashed"} = params) do
    route_tracked(params, "squashed_at")
  end

  defp route_tracked(params, ended_field) do
    with {:ok, started_at} <- Timex.parse(params["started_at"], "{RFC3339z}"),
         {:ok, ended_at} <- Timex.parse(params[ended_field], "{RFC3339z}") do
      duration = Timex.diff(ended_at, started_at, :milliseconds)
      {:ok, %{"command" => params["command"],
              "aggregate_id" => Veggy.MongoDB.ObjectId.from_string(params["timer_id"]),
              "aggregate_module" => __MODULE__,
              "started_at" => started_at,
              ended_field => ended_at,
              "duration" => duration,
              "description" => Map.get(params, "description", ""),
              "_id" => Veggy.UUID.new}}
    else
      _ ->
        {:error, "Wrong time format"}
    end
  end

  def init(id) do
    Veggy.EventStore.subscribe(self, &match?(%{"event" => "PomodoroCompleted", "aggregate_id" => ^id}, &1))
    %{"id" => id, "ticking" => false}
  end

  def handle(%{"command" => "CreateTimer", "user_id" => user_id} = command, aggregate) do
    {:ok, %{"event" => "TimerCreated",
            "command_id" => command["_id"],
            "aggregate_id" => aggregate["id"],
            "timer_id" => aggregate["id"],
            "user_id" => user_id,
            "_id" => Veggy.UUID.new}}
  end
  def handle(%{"command" => "StartPomodoro"}, %{"ticking" => true}), do: {:error, "Pomodoro is ticking"}
  def handle(%{"command" => "StartPomodoro"} = command, aggregate) do
    {:ok, pomodoro_id} = Veggy.Countdown.start(command["duration"], aggregate["id"], aggregate["user_id"], command["_id"])
    {:ok, %{"event" => "PomodoroStarted",
            "pomodoro_id" => pomodoro_id,
            "user_id" => aggregate["user_id"],
            "command_id" => command["_id"],
            "aggregate_id" => aggregate["id"],
            "timer_id" => aggregate["id"],
            "duration" => command["duration"],
            "description" => command["description"],
            "shared_with" => command["shared_with"],
            "_id" => Veggy.UUID.new}}
  end
  def handle(%{"command" => "SquashPomodoro"}, %{"ticking" => false}), do: {:error, "Pomodoro is not ticking, nothing to squash"}
  def handle(%{"command" => "SquashPomodoro"} = command, %{"pomodoro_id" => pomodoro_id} = aggregate) do
    :ok = Veggy.Countdown.squash(pomodoro_id)
    {:ok, %{"event" => "PomodoroSquashed",
            "pomodoro_id" => pomodoro_id,
            "user_id" => aggregate["user_id"],
            "command_id" => command["_id"],
            "aggregate_id" => aggregate["id"],
            "timer_id" => aggregate["id"],
            "reason" => command["reason"],
            "_id" => Veggy.UUID.new,
           }}
  end
  def handle(%{"command" => "StartSharedPomodoro", "shared_with" => shared_with} = command, aggregate) do
    pairs = [aggregate["id"] | shared_with]
    commands = Enum.map(pairs,
      fn(id) -> %{"command" => "StartPomodoro",
                  "aggregate_id" => id,
                  "aggregate_module" => __MODULE__,
                  "duration" => command["duration"],
                  "description" => command["description"],
                  "shared_with" => pairs -- [id],
                  "_id" => Veggy.UUID.new}
      end)
    {:ok, [], {:fork, commands}}
  end
  def handle(%{"command" => "SquashSharedPomodoro"} = command, %{"shared_with" => shared_with} = aggregate) do
    pairs = [aggregate["id"] | shared_with]
    commands = Enum.map(pairs, fn(timer_id) ->
      %{command | "command" => "SquashPomodoro", "aggregate_id" => timer_id, "_id" => Veggy.UUID.new}
    end)
    {:ok, [], commands}
  end
  def handle(%{"command" => "TrackPomodoroCompleted"} = command, aggregate) do
    handle_track(command, "completed_at", "PomodoroCompletedTracked", aggregate)
  end
  def handle(%{"command" => "TrackPomodoroSquashed"} = command, aggregate) do
    handle_track(command, "squashed_at", "PomodoroSquashedTracked", aggregate)
  end

  defp handle_track(command, ended_field, event_name, aggregate) do
    if ended_before?(command, ended_field, Timex.now) do

      events = Veggy.Projection.events_where(Veggy.Projection.Pomodori, {:aggregate_id, aggregate["id"]})
      pomodori = Veggy.Projection.process(Veggy.Projection.Pomodori, events)

      if compatible?(pomodori, command["started_at"], command[ended_field]) do
        {:ok, %{"event" => event_name,
                "pomodoro_id" => Veggy.UUID.new,
                "duration" => command["duration"],
                "description" => command["description"],
                "started_at" => command["started_at"],
                ended_field => command[ended_field],
                "user_id" => aggregate["user_id"],
                "command_id" => command["_id"],
                "aggregate_id" => aggregate["id"],
                "timer_id" => aggregate["id"],
                "_id" => Veggy.UUID.new}}
      else
        {:error, "Another pomodoro was ticking between #{command["started_at"]} and #{command[ended_field]}"}
      end
    else
      {:error, "Seems like you want to track a pomodoro that is not in the past... :-/"}
    end
  end

  # "TODO" => ensure that the current pomodoro has been started by the same command we are rolling back
  def rollback(%{"command" => "StartPomodoro"}, %{"ticking" => false}), do: {:error, "Pomodoro is not ticking"}
  def rollback(%{"command" => "StartPomodoro"} = command, %{"pomodoro_id" => pomodoro_id} = aggregate) do
    :ok = Veggy.Countdown.void(pomodoro_id)
    {:ok, %{"event" => "PomodoroVoided",
            "pomodoro_id" => pomodoro_id,
            "user_id" => aggregate["user_id"],
            "command_id" => command["_id"],
            "aggregate_id" => aggregate["id"],
            "timer_id" => aggregate["id"],
            "_id" => Veggy.UUID.new}}
  end


  def process(%{"event" => "TimerCreated", "user_id" => user_id}, s),
    do: Map.put(s, "user_id", user_id)
  def process(%{"event" => "PomodoroStarted", "pomodoro_id" => pomodoro_id, "shared_with" => shared_with}, s),
    do: s |> Map.put("ticking", true) |> Map.put("pomodoro_id", pomodoro_id) |> Map.put("shared_with", shared_with)
  def process(%{"event" => "PomodoroSquashed"}, s),
    do: s |> Map.put("ticking", false) |> Map.delete("pomodoro_id") |> Map.delete("shared_with")
  def process(%{"event" => "PomodoroCompleted"}, s),
    do: s |> Map.put("ticking", false) |> Map.delete("pomodoro_id") |> Map.delete("shared_with")
  def process(%{"event" => "PomodoroVoided"}, s),
      do: s |> Map.put("ticking", false) |> Map.delete("pomodoro_id") |> Map.delete("shared_with")
  def process(_, s), do: s


  # TODO: defpt previous `require Testable`
  def compatible?(pomodori, started_at, ended_at) do
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

  defp ended_before?(command, ended_field, t), do: Timex.before?(command[ended_field], t)
end

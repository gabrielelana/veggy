defmodule Veggy.Aggregate.Timer do
  @default_duration 1_500_000   # 25 minutes in milliseconds

  # @behaviour Veggy.Aggregate
  use Veggy.MongoDB.Aggregate, collection: "aggregate.timers"

  def route(%{"command" => "StartPomodoro"} = params) do
    # validate params do
    #   timer_id <- required("timer_id") |> to(:mongoid)
    #   duration <- optional("duration", "")
    #   description <- optional("description", "")
    #   shared_with <- optional("shared_with", [])
    #   command("StartPomodoro", timer_id, [duration, description, shared_with])
    # end
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
  def route(_), do: nil

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
end

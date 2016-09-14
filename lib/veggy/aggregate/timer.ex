defmodule Veggy.Aggregate.Timer do
  @default_duration 1_500_000   # 25 minutes in milliseconds

  # @behaviour Veggy.Aggregate
  use Veggy.MongoDB.Aggregate, collection: "aggregate.timers"

  def route(%Plug.Conn{params: %{"command" => "StartPomodoro"} = params}) do
    {:ok, %{command: "StartPomodoro",
            aggregate_id: Veggy.MongoDB.ObjectId.from_string(params["timer_id"]),
            aggregate_module: __MODULE__,
            duration: Map.get(params, "duration", @default_duration),
            description: Map.get(params, "description", ""),
            shared_with: Map.get(params, "shared_with", []),
            id: Veggy.UUID.new}}
  end
  def route(%Plug.Conn{params: %{"command" => "SquashPomodoro"} = params}) do
    {:ok, %{command: "SquashPomodoro",
            aggregate_id: Veggy.MongoDB.ObjectId.from_string(params["timer_id"]),
            aggregate_module: __MODULE__,
            reason: Map.get(params, "reason", ""),
            shared_with: Map.get(params, "shared_with", []),
            id: Veggy.UUID.new}}
  end
  def route(%Plug.Conn{params: %{"command" => "StartSharedPomodoro"} = params}) do
    {:ok, %{command: "StartSharedPomodoro",
            aggregate_id: Veggy.MongoDB.ObjectId.from_string(params["timer_id"]),
            aggregate_module: __MODULE__,
            duration: Map.get(params, "duration", @default_duration),
            description: Map.get(params, "description", ""),
            shared_with: Map.get(params, "shared_with", []) |> Enum.map(&Veggy.MongoDB.ObjectId.from_string/1),
            id: Veggy.UUID.new}}
  end
  def route(_), do: nil

  def init(id) do
    Veggy.EventStore.subscribe(self, &match?(%{event: "PomodoroEnded", aggregate_id: ^id}, &1))
    %{"id" => id, "ticking" => false}
  end

  def handle(%{command: "CreateTimer", user_id: user_id} = command, aggregate) do
    {:ok, %{event: "TimerCreated",
            command_id: command.id,
            aggregate_id: aggregate["id"],
            timer_id: aggregate["id"],
            user_id: user_id,
            id: Veggy.UUID.new}}
  end
  def handle(%{command: "StartPomodoro"}, %{"ticking" => true}), do: {:error, "Pomodoro is ticking"}
  def handle(%{command: "StartPomodoro"} = command, aggregate) do
    {:ok, pomodoro_id} = Veggy.Countdown.start(command.duration, aggregate["id"], aggregate["user_id"])
    {:ok, %{event: "PomodoroStarted",
            pomodoro_id: pomodoro_id,
            user_id: aggregate["user_id"],
            command_id: command.id,
            aggregate_id: aggregate["id"],
            timer_id: aggregate["id"],
            duration: command.duration,
            description: command.description,
            id: Veggy.UUID.new}}
  end
  def handle(%{command: "SquashPomodoro"}, %{"ticking" => false}), do: {:error, "Pomodoro is not ticking"}
  def handle(%{command: "SquashPomodoro"} = command, %{"pomodoro_id" => pomodoro_id} = aggregate) do
    :ok = Veggy.Countdown.squash(pomodoro_id)
    {:ok, %{event: "PomodoroSquashed",
            pomodoro_id: pomodoro_id,
            user_id: aggregate["user_id"],
            command_id: command.id,
            aggregate_id: aggregate["id"],
            timer_id: aggregate["id"],
            reason: command.reason,
            id: Veggy.UUID.new}}
  end
  def handle(%{command: "StartSharedPomodoro", shared_with: shared_with} = command, aggregate) do
    buddies = [aggregate["id"] | shared_with]
    commands = Enum.map(buddies,
      fn(id) -> %{command: "StartPomodoro",
                  aggregate_id: id,
                  aggregate_module: __MODULE__,
                  duration: command.duration,
                  description: command.description,
                  shared_with: buddies -- [id],
                  id: Veggy.UUID.new}
      end)
    {:ok, [], {:fork, commands}}
  end

  # TODO: ensure that the current pomodoro has been started by the same command we are rolling back
  def rollback(%{command: "StartPomodoro"}, %{"ticking" => false}), do: {:error, "Pomodoro is not ticking"}
  def rollback(%{command: "StartPomodoro"} = command, %{"pomodoro_id" => pomodoro_id} = aggregate) do
    :ok = Veggy.Countdown.void(pomodoro_id)
    {:ok, %{event: "PomodoroVoided",
            pomodoro_id: pomodoro_id,
            user_id: aggregate["user_id"],
            command_id: command.id,
            aggregate_id: aggregate["id"],
            timer_id: aggregate["id"],
            id: Veggy.UUID.new}}
  end


  def process(%{event: "TimerCreated", user_id: user_id}, s),
    do: Map.put(s, "user_id", user_id)

  def process(%{event: "PomodoroStarted", pomodoro_id: pomodoro_id}, s),
    do: s |> Map.put("ticking", true) |> Map.put("pomodoro_id", pomodoro_id)

  def process(%{event: "PomodoroSquashed"}, s),
    do: s |> Map.put("ticking", false) |> Map.delete("pomodoro_id")

  def process(%{event: "PomodoroEnded"}, s),
    do: s |> Map.put("ticking", false) |> Map.delete("pomodoro_id")

  def process(%{event: "PomodoroVoided"}, s),
    do: s |> Map.put("ticking", false) |> Map.delete("pomodoro_id")

  def process(_, s), do: s
end

defmodule Veggy.Projection.LatestPomodori do
  # TODO: @behaviour Projection
  # TODO: use Veggy.Mongo.Projection, collection: "projection.latest_pomodori"
  @collection "projection.latest_pomodori"

  def init do
    Veggy.EventStore.subscribe(self, &match?(%{event: "LoggedIn"}, &1))
    Veggy.EventStore.subscribe(self, &match?(%{event: "PomodoroStarted"}, &1))
    Veggy.EventStore.subscribe(self, &match?(%{event: "PomodoroEnded"}, &1))
    Veggy.EventStore.subscribe(self, &match?(%{event: "PomodoroSquashed"}, &1))
  end

  def fetch(%{event: _, user_id: user_id}) do
    case Mongo.find(Veggy.MongoDB, @collection, %{"user_id" => user_id}) |> Enum.to_list do
      [] -> %{"_id" => Veggy.UUID.new, "user_id" => user_id}
      [d] -> d
    end
  end

  def store(record) do
    Mongo.save_one(Veggy.MongoDB, @collection, record)
  end

  def process(%{event: "LoggedIn", user_id: user_id, username: username}, record) do
    record
    |> Map.put("user_id", user_id)
    |> Map.put("username", username)
  end

  # NOTE: this means that the events must be ordered...
  # TODO: projection as FSM that can push back events that are not in the wanted order?
  def process(%{event: "PomodoroStarted"} = event, record) do
    record
    |> Map.put("started_at", event.received_at)
    |> Map.put("duration", event.duration)
    |> Map.put("ticking", true)
  end
  def process(%{event: "PomodoroEnded"} = event, record) do
    record
    |> Map.put("ended_at", event.received_at)
    |> Map.put("ticking", false)
    |> Map.delete("duration")
  end
  def process(%{event: "PomodoroSquashed"} = event, record) do
    record
    |> Map.put("squashed_at", event.received_at)
    |> Map.put("ticking", false)
    |> Map.delete("duration")
  end

  def all do
    case Mongo.find(Veggy.MongoDB, @collection, %{}) |> Enum.to_list do
      [] -> {:ok, []}
      d -> {:ok, d |> Enum.map(&Map.delete(&1, "_id"))}
    end
  end
end

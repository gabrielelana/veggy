defmodule Veggy.Projection.LatestPomodori do
  # "TODO" => @behaviour Projection
  # "TODO" => use Veggy.Mongo.Projection, "collection" => "projection.latest_pomodori"
  @collection "projection.latest_pomodori"

  def init do
    Veggy.EventStore.subscribe(self, &match?(%{"event" => "LoggedIn"}, &1))
    Veggy.EventStore.subscribe(self, &match?(%{"event" => "PomodoroStarted"}, &1))
    Veggy.EventStore.subscribe(self, &match?(%{"event" => "PomodoroSquashed"}, &1))
    Veggy.EventStore.subscribe(self, &match?(%{"event" => "PomodoroEnded"}, &1))
  end


  def fetch(%{"event" => _, "timer_id" => timer_id}) do
    case Mongo.find(Veggy.MongoDB, @collection, %{"timer_id" => timer_id}) |> Enum.to_list do
      [] -> %{"_id" => Veggy.UUID.new, "timer_id" => timer_id}
      [d] -> d
    end
  end


  def store(record) do
    Mongo.save_one(Veggy.MongoDB, @collection, record)
  end


  def process(%{"event" => "LoggedIn"} = event, record) do
    record
    |> Map.put("user_id", event["user_id"])
    |> Map.put("timer_id", event["timer_id"])
    |> Map.put("username", event["username"])
  end


  # "NOTE" => this means that the events must be ordered...
  # "TODO" => projection as FSM that can push back events that are not in the wanted order?
  def process(%{"event" => "PomodoroStarted"} = event, record) do
    record
    |> Map.put("started_at", event["received_at"])
    |> Map.put("duration", event["duration"])
    |> Map.put("ticking", true)
    |> Map.delete("ended_at")
    |> Map.delete("squashed_at")
  end

  def process(%{"event" => "PomodoroEnded"} = event, record) do
    record
    |> Map.put("ended_at", event["received_at"])
    |> Map.put("ticking", false)
  end

  def process(%{"event" => "PomodoroSquashed"} = event, record) do
    record
    |> Map.put("squashed_at", event["received_at"])
    |> Map.put("ticking", false)
  end


  def query("latest-pomodoro", %{"timer_id" => timer_id}) do
    timer_id = Veggy.MongoDB.ObjectId.from_string(timer_id)
    query = %{"timer_id" => timer_id, "started_at" => %{"$exists" => true}}
    case Mongo.find(Veggy.MongoDB, @collection, query) |> Enum.to_list do
      [d] -> {:ok, d}
      [] -> {:not_found, :record}
    end
  end

  def query("latest-pomodori", _) do
    query = %{"started_at" => %{"$exists" => true}}
    Mongo.find(Veggy.MongoDB, @collection, query)
    |> Enum.map(&Map.delete(&1, "_id"))
    |> (&{:ok, &1}).()
  end

  def query(_, _), do: nil
end

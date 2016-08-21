defmodule Veggy.Projection.Pomodori do
  # TODO: @behaviour Projection
  # TODO: use Veggy.Mongo.Projection, collection: "projection.pomodori"
  @collection "projection.pomodori"

  # RECORD:
  # - pomodoro_id
  # - timer_id
  # - started_at
  # - ended_at
  # - squashed_at
  # - ticking
  # - description
  # - duration

  # "PomodoroStarted": aggregate_id, pomodoro_id, command_id, duration
  # "PomodoroEnded": aggregate_id, pomodoro_id

  def init do
    Veggy.EventStore.subscribe(self, &match?(%{event: "PomodoroStarted"}, &1))
    Veggy.EventStore.subscribe(self, &match?(%{event: "PomodoroEnded"}, &1))
    # TODO: create appropriate indexes
  end

  def fetch(%{pomodoro_id: pomodoro_id}) do
    case Mongo.find(Veggy.MongoDB, @collection, %{"pomodoro_id" => pomodoro_id}) |> Enum.to_list do
      [] -> %{}
      [d] -> d
    end
  end

  def store(record) do
    Mongo.save_one(Veggy.MongoDB, @collection, record)
  end

  def process(%{event: "PomodoroStarted"} = event, %{}) do
    %{"pomodoro_id" => event.pomodoro_id,
      "timer_id" => event.aggregate_id,
      "started_at" => event.received_at,
      "ticking" => true,
      "duration" => event.duration}
  end
  def process(%{event: "PomodoroEnded"} = event, record) do
    record
    |> Map.put("ended_at", event.received_at)
    |> Map.put("ticking", false)
  end

  def latest_pomodoro_for_timer(timer_id) do
    query = %{"timer_id" => timer_id}
    options = [sort: %{"started_at" => -1}, limit: 1]
    case Mongo.find(Veggy.MongoDB, @collection, query, options) |> Enum.to_list do
      [] -> {:error, :not_found}
      [d] -> {:ok, d}
    end
  end
end

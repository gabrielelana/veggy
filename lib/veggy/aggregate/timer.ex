defmodule Veggy.Aggregate.Timer do
  # TODO: @behaviour Veggy.Aggregate
  # TODO: use Veggy.Mongo.Aggregate, collection: "aggregate.timers"
  @collection "aggregate.timers"

  def init(id) do
    Veggy.EventStore.subscribe(self, &match?(%{event: "PomodoroEnded", aggregate_id: id}, &1))
    %{"id" => id, "ticking" => false}
  end

  def fetch(id, initial) do
    case Mongo.find(Veggy.MongoDB, @collection, %{"_id" => id}) |> Enum.to_list do
      [] -> initial
      [d] -> d |> Map.put("id", d["_id"]) |> Map.delete("_id")
    end
  end

  def store(aggregate) do
    aggregate = aggregate |> Map.put("_id", aggregate["id"]) |> Map.delete("id")
    {:ok, _} = Mongo.update_one(Veggy.MongoDB, @collection,
      %{"_id" => aggregate["_id"]}, %{"$set" => aggregate}, upsert: true)
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

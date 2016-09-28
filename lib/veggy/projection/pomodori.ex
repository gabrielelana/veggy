defmodule Veggy.Projection.Pomodori do
  # TODO: @behaviour Projection
  # TODO: use Veggy.Mongo.Projection, collection: "projection.pomodori"
  @collection "projection.pomodori"

  def init do
    Veggy.MongoDB.create_index(@collection, %{"_offset" => 1})
    {:ok, offset, ["PomodoroStarted", "PomodoroSquashed", "PomodoroCompleted", "PomodoroVoided"]}
  end

  # TODO: put into Veggy.Mongo.Projection
  def offset do
    query = %{"_offset" => %{"$exists" => true}}
    options = [order_by: %{"_offset" => -1}, projection: %{"_offset" => 1}, limit: 1]
    case Mongo.find(Veggy.MongoDB, @collection, query, options) |> Enum.to_list do
      [] -> -1
      [%{"_offset" => offset}] -> offset
    end
  end

  # TODO: put into Veggy.Mongo.Projection
  def fetch(%{"pomodoro_id" => pomodoro_id}) do
    case Mongo.find(Veggy.MongoDB, @collection, %{"pomodoro_id" => pomodoro_id}) |> Enum.to_list do
      [] -> %{}
      [d] -> d
    end
  end

  # TODO: put into Veggy.Mongo.Projection
  def store(record, offset) do
    Mongo.save_one(Veggy.MongoDB, @collection, record |> Map.put("_offset", offset))
  end

  # TODO: put into Veggy.Mongo.Projection
  def delete(record, offset) do
    Mongo.delete_one(Veggy.MongoDB, @collection, %{"_id" => record["_id"]})
    Mongo.save_one(Veggy.MongoDB, @collection, %{"_id" => "_offset", "_offset" => offset})
  end


  def process(%{"event" => "PomodoroStarted"} = event, %{}) do
    %{"pomodoro_id" => event["pomodoro_id"],
      "timer_id" => event["aggregate_id"],
      "started_at" => event["received_at"],
      "tags" => Veggy.Task.extract_tags(event["description"]),
      "shared_with" => event["shared_with"],
      "status" => "started",
      "duration" => event["duration"]}
  end
  def process(%{"event" => "PomodoroCompleted"} = event, record) do
    record
    |> Map.put("completed_at", event["received_at"])
    |> Map.put("status", "completed")
  end
  def process(%{"event" => "PomodoroSquashed"} = event, record) do
    record
    |> Map.put("squashed_at", event["received_at"])
    |> Map.put("status", "squashed")
  end
  def process(%{"event" => "PomodoroVoided"}, _) do
    :delete
  end


  def query("pomodori-by-tag", %{"tag" => tag, "timer_id" => timer_id}) do
    timer_id = Veggy.MongoDB.ObjectId.from_string(timer_id)
    tags = String.split(tag, ",", trim: true) |> Enum.map(&String.trim/1) |> Enum.map(&String.downcase/1)
    query = %{"timer_id" => timer_id, "tags" => %{"$in" => tags}}
    Mongo.find(Veggy.MongoDB, @collection, query)
    |> Enum.to_list
    |> (&{:ok, &1}).()
  end

  # TODO
  # Veggy.Mongo.Projection.find(
  #   @collection,
  #   %{"timer_id" => timer_id
  #     "started_at" => %{"$gte" => Timex.beginning_of_day(day),
  #                       "$lte" => Timex.end_of_day(day)}})

  def query("pomodori-of-the-day", %{"day" => day, "timer_id" => timer_id} = parameters) do
    timer_id = Veggy.MongoDB.ObjectId.from_string(timer_id)
    case Timex.parse(day, "{YYYY}-{0M}-{0D}") do
      {:ok, day} ->
        beginning_of_day =
          day |> Timex.beginning_of_day |> Timex.to_datetime |> Veggy.MongoDB.DateTime.from_datetime
        end_of_day =
          day |> Timex.end_of_day |> Timex.to_datetime |> Veggy.MongoDB.DateTime.from_datetime
        query = %{"started_at" => %{"$gte" => beginning_of_day, "$lte" => end_of_day},
                  "timer_id" => timer_id,
                 }
        Mongo.find(Veggy.MongoDB, @collection, query)
        |> Enum.to_list
        |> (&{:ok, &1}).()
      {:error, reason} ->
        {:error, "day=#{parameters["day"]}: #{reason}"}
    end
  end

  def query(_, _), do: nil
end

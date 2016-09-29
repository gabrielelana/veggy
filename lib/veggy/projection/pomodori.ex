defmodule Veggy.Projection.Pomodori do
  use Veggy.MongoDB.Projection,
    collection: "projection.pomodori",
    events: ["PomodoroStarted", "PomodoroSquashed", "PomodoroCompleted", "PomodoroVoided"],
    field: "pomodoro_id"


  def process(%{"event" => "PomodoroStarted"} = event, %{}) do
    %{"pomodoro_id" => event["pomodoro_id"],
      "timer_id" => event["aggregate_id"],
      "started_at" => event["_received_at"],
      "tags" => Veggy.Task.extract_tags(event["description"]),
      "shared_with" => event["shared_with"],
      "status" => "started",
      "duration" => event["duration"]}
  end
  def process(%{"event" => "PomodoroCompleted"} = event, record) do
    record
    |> Map.put("completed_at", event["_received_at"])
    |> Map.put("status", "completed")
  end
  def process(%{"event" => "PomodoroSquashed"} = event, record) do
    record
    |> Map.put("squashed_at", event["_received_at"])
    |> Map.put("status", "squashed")
  end
  def process(%{"event" => "PomodoroVoided"}, _) do
    :delete
  end


  def query("pomodori-by-tag", %{"tag" => tag, "timer_id" => timer_id}) do
    timer_id = Veggy.MongoDB.ObjectId.from_string(timer_id)
    tags = String.split(tag, ",", trim: true) |> Enum.map(&String.trim/1) |> Enum.map(&String.downcase/1)
    find(%{"timer_id" => timer_id, "tags" => %{"$in" => tags}})
  end

  def query("pomodori-of-the-day", %{"day" => day, "timer_id" => timer_id} = parameters) do
    timer_id = Veggy.MongoDB.ObjectId.from_string(timer_id)
    case Timex.parse(day, "{YYYY}-{0M}-{0D}") do
      {:ok, day} ->
        beginning_of_day =
          day |> Timex.beginning_of_day |> Timex.to_datetime |> Veggy.MongoDB.DateTime.from_datetime
        end_of_day =
          day |> Timex.end_of_day |> Timex.to_datetime |> Veggy.MongoDB.DateTime.from_datetime
        find(%{"started_at" => %{"$gte" => beginning_of_day, "$lte" => end_of_day},
               "timer_id" => timer_id,
              })
      {:error, reason} ->
        {:error, "day=#{parameters["day"]}: #{reason}"}
    end
  end

  def query(_, _), do: nil
end

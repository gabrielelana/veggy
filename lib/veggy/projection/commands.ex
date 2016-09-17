defmodule Veggy.Projection.Commands do
  # TODO: @behaviour Projection
  # TODO: use Veggy.Mongo.Projection, collection: "projection.commands"
  @collection "projection.commands"

  # TODO: callback
  def init do
    # Veggy.EventStore.subscribe(self, &match?(%{"event" => "CommandReceived"}, &1))
    # Veggy.EventStore.subscribe(self, &match?(%{"event" => "CommandSucceeded"}, &1))
    # Veggy.EventStore.subscribe(self, &match?(%{"event" => "CommandHandedOver"}, &1))
    # Veggy.EventStore.subscribe(self, &match?(%{"event" => "CommandRolledBack"}, &1))
    # Veggy.EventStore.subscribe(self, &match?(%{"event" => "CommandFailed"}, &1))
    Veggy.EventStore.subscribe(self, &match?(%{"command_id" => _}, &1))
    %{}
  end

  # TODO: callback for Veggy.Mongo.Projection
  def index(%{"command_id" => command_id}), do: %{"command_id" => command_id}

  # TODO: callback but implemented by Veggy.Mongo.Projection
  def fetch(event) do
    case Mongo.find(Veggy.MongoDB, @collection, index(event)) |> Enum.to_list do
      [] -> %{}
      [d] -> d
    end
  end

  # TODO: callback but implemented by Veggy.Mongo.Projection
  def store(record) do
    Mongo.save_one(Veggy.MongoDB, @collection, record)
  end


  def process(%{"event" => "CommandReceived"} = event, _) do
    %{"command_id" => event["command_id"],
      "command" => event["command"],
      "received_at" => event["received_at"],
      "status" => "received",
    }
  end
  def process(%{"event" => "CommandSucceeded"} = event, record) do
    received_at = Veggy.MongoDB.DateTime.to_datetime(record["received_at"])
    succeeded_at = Veggy.MongoDB.DateTime.to_datetime(event["received_at"])
    elapsed = trunc(Timex.diff(succeeded_at, received_at) / 1_000)
    record
    |> Map.put("status", "succeeded")
    |> Map.put("succeeded_at", event["received_at"])
    |> Map.put("commands", Enum.concat(Map.get(record, "commands", []), Map.get(event, "commands", [])))
    |> Map.put("events", Enum.concat(Map.get(record, "events", []), Map.get(event, "events", [])))
    |> Map.put("elapsed", elapsed)
  end
  def process(%{"event" => "CommandFailed"} = event, record) do
    received_at = Veggy.MongoDB.DateTime.to_datetime(record["received_at"])
    failed_at = Veggy.MongoDB.DateTime.to_datetime(event["received_at"])
    elapsed = trunc(Timex.diff(failed_at, received_at) / 1_000)
    record
    |> Map.put("status", "failed")
    |> Map.put("failed_at", event["received_at"])
    |> Map.put("why", event["why"])
    |> Map.put("commands", Enum.concat(Map.get(record, "commands", []), Map.get(event, "commands", [])))
    |> Map.put("events", Enum.concat(Map.get(record, "events", []), Map.get(event, "events", [])))
    |> Map.put("elapsed", elapsed)
  end
  def process(%{"event" => "CommandHandedOver"} = event, record) do
    record
    |> Map.put("status", "working")
    |> Map.put("commands", Enum.concat(Map.get(record, "commands", []), Map.get(event, "commands", [])))
    |> Map.put("events", Enum.concat(Map.get(record, "events", []), Map.get(event, "events", [])))
  end
  def process(%{"event" => "CommandRolledBack"} = event, record) do
    received_at = Veggy.MongoDB.DateTime.to_datetime(record["received_at"])
    rolledback_at = Veggy.MongoDB.DateTime.to_datetime(event["received_at"])
    elapsed = trunc(Timex.diff(rolledback_at, received_at) / 1_000)
    record
    |> Map.put("status", "rolledback")
    |> Map.put("rolledback_at", event["received_at"])
    |> Map.put("commands", Enum.concat(Map.get(record, "commands", []), Map.get(event, "commands", [])))
    |> Map.put("events", Enum.concat(Map.get(record, "events", []), Map.get(event, "events", [])))
    |> Map.put("elapsed", elapsed)
  end
  def process(%{"id" => event_id}, record) do
    Map.put(record, "events",
      Map.get(record, "events", [])
      |> MapSet.new
      |> MapSet.put(event_id)
      |> MapSet.to_list
    )
  end


  def query("command-status", %{"command_id" => command_id}) do
    command_id = Veggy.MongoDB.ObjectId.from_string(command_id)
    case Mongo.find(Veggy.MongoDB, @collection, %{"command_id" => command_id}) |> Enum.to_list do
      [%{"command_id" => ^command_id} = command] -> {:ok, command}
      _ -> {:not_found, :record}
    end
  end
  def query(_, _), do: nil
end

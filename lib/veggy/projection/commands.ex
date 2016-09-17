defmodule Veggy.Projection.Commands do
  # TODO: @behaviour Projection
  # TODO: use Veggy.Mongo.Projection, collection: "projection.commands"
  @collection "projection.commands"

  def init do
    Veggy.EventStore.subscribe(self, &match?(%{"event" => "CommandSucceeded"}, &1))
    Veggy.EventStore.subscribe(self, &match?(%{"event" => "CommandFailed"}, &1))
    # "TODO" => create appropriate indexs
  end

  def fetch(%{"event" => _, "command_id" => command_id}) do
    case Mongo.find(Veggy.MongoDB, @collection, %{"command_id" => command_id}) |> Enum.to_list do
      [] -> %{}
      [d] -> d
    end
  end

  def store(record) do
    Mongo.save_one(Veggy.MongoDB, @collection, record)
  end

  def process(%{"event" => "CommandSucceeded", "command_id" => command_id}, _) do
    %{"command_id" => command_id, "status" => "succeeded"}
  end
  def process(%{"event" => "CommandFailed", "command_id" => command_id}, _) do
    %{"command_id" => command_id, "status" => "failed"}
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

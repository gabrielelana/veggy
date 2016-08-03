defmodule Veggy.Projection.Commands do
  # TODO: @behaviour Projection
  # TODO: use Veggy.Mongo.Projection, collection: "projection.commands"
  @collection "projection.commands"

  def init do
    Veggy.EventStore.subscribe(self, &match?(%{event: "CommandReceived"}, &1))
    Veggy.EventStore.subscribe(self, &match?(%{event: "CommandSucceeded"}, &1))
    Veggy.EventStore.subscribe(self, &match?(%{event: "CommandFailed"}, &1))
    # TODO: create appropriate indexs
  end

  def fetch(%{command_id: command_id}) do
    case Mongo.find(Veggy.MongoDB, @collection, %{"command_id" => command_id}) |> Enum.to_list do
      [] -> %{}
      [d] -> d
    end
  end

  def store(record) do
    Mongo.save_one(Veggy.MongoDB, @collection, record)
  end

  def process(%{event: "CommandReceived"} = event, %{}) do
    %{"command_id" => event.command_id, "status" => "received"}
  end
  def process(%{event: "CommandSucceeded"}, command) do
    %{command | "status" => "succeded"}
  end
  def process(%{event: "CommandFailed"}, command) do
    %{command | "status" => "failed"}
  end

  def status_of(command_id) do
    case fetch(%{command_id: command_id}) do
      %{"command_id" => ^command_id} = command -> {:ok, command}
      _ -> {:error, :not_found}
    end
  end
end

defmodule Veggy.Aggregate.User do
  # @behaviour Veggy.Aggregate
  # use Veggy.Mongo.Aggregate, collection: "aggregate.users"

  @collection "aggregate.users"

  def route(%Plug.Conn{params: %{"command" => "Login", "username" => username} = params}) do
    {:ok, %{command: params["command"],
            username: username,
            aggregate_id: "user/#{username}",
            aggregate_module: __MODULE__,
            id: Veggy.UUID.new}}
  end
  def route(_), do: nil

  def init(id) do
    %{"id" => id, "timer_id" => Veggy.UUID.new}
  end

  # TODO: implemented by Veggy.Mongo.Aggregate
  def fetch(id, initial) do
    case Mongo.find(Veggy.MongoDB, @collection, %{"_id" => id}) |> Enum.to_list do
      [] -> initial
      [d] -> d |> Map.put("id", d["_id"]) |> Map.delete("_id")
    end
  end

  # TODO: implemented by Veggy.Mongo.Aggregate
  def store(aggregate) do
    aggregate = aggregate |> Map.put("_id", aggregate["id"]) |> Map.delete("id")
    {:ok, _} = Mongo.update_one(Veggy.MongoDB, @collection,
      %{"_id" => aggregate["_id"]}, %{"$set" => aggregate}, upsert: true)
  end

  def handle(%{command: "Login"} = command, aggregate) do
    {:ok, %{event: "LoggedIn",
            username: command.username,
            command_id: command.id,
            aggregate_id: aggregate["id"],
            timer_id: aggregate["timer_id"],
            id: Veggy.UUID.new}}
  end

  def process(_event, aggregate), do: aggregate
end

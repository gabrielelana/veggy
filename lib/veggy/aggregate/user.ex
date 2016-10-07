defmodule Veggy.Aggregate.User do
  # @behaviour Veggy.Aggregate || use Veggy.Aggregate
  use Veggy.MongoDB.Aggregate, collection: "aggregate.users"


  def route(%{"command" => "Login", "username" => username} = params) do
    {:ok, %{"command" => params["command"],
            "username" => username,
            "aggregate_id" => "user/#{username}",
            "aggregate_module" => __MODULE__,
            "_id" => Veggy.UUID.new}}
  end


  def init(id) do
    {:ok, %{"id" => id, "timer_id" => Veggy.UUID.new}}
  end


  def check(state) do
    {:ok, state}
  end


  def handle(%{"command" => "Login"} = command, aggregate) do
    event = %{"event" => "LoggedIn",
              "username" => command["username"],
              "user_id" => aggregate["id"],
              "aggregate_id" => aggregate["id"],
              "command_id" => command["_id"],
              "timer_id" => aggregate["timer_id"],
              "_id" => Veggy.UUID.new}
    command = %{"command" => "CreateTimer",
                "aggregate_id" => aggregate["timer_id"],
                "aggregate_module" => Veggy.Aggregate.Timer,
                "user_id" => aggregate["id"],
                "_id" => Veggy.UUID.new}
    {:ok, [event], [command]}
  end


  def process(%{"event" => "LoggedIn", "username" => username}, aggregate),
    do: Map.put(aggregate, "username", username)
  def process(_event, aggregate),
    do: aggregate
end

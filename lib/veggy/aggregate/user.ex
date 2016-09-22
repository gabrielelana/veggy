defmodule Veggy.Aggregate.User do
  # @behaviour Veggy.Aggregate
  # use Veggy.Aggregate
  use Veggy.MongoDB.Aggregate, collection: "aggregate.users"

  def route(%{"command" => "Login", "username" => username, "client_id" => client_id}) do
    {:ok, %{"command" => "Login",
            "username" => username,
            "client_id" => client_id,
            "aggregate_id" => "user/#{username}",
            "aggregate_module" => __MODULE__,
            "id" => Veggy.UUID.new}}
  end
  def route(_), do: nil

  def init(id) do
    %{"id" => id, "timer_id" => Veggy.UUID.new}
  end

  def handle(%{"command" => "Login"} = command, aggregate) do
    event = %{"event" => "LoggedIn",
              "username" => command["username"],
              "user_id" => aggregate["id"],
              "client_id" => command["client_id"],
              "aggregate_id" => aggregate["id"],
              "command_id" => command["id"],
              "timer_id" => aggregate["timer_id"],
              "id" => Veggy.UUID.new}
    command = %{"command" => "CreateTimer",
                "aggregate_id" => aggregate["timer_id"],
                "aggregate_module" => Veggy.Aggregate.Timer,
                "user_id" => aggregate["id"],
                "id" => Veggy.UUID.new}
    {:ok, [event], [command]}
  end

  def process(%{"event" => "LoggedIn", "username" => username}, aggregate),
    do: Map.put(aggregate, "username", username)

  def process(_event, aggregate),
    do: aggregate
end

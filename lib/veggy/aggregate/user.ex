defmodule Veggy.Aggregate.User do
  # @behaviour Veggy.Aggregate
  # use Veggy.Aggregate
  use Veggy.MongoDB.Aggregate, collection: "aggregate.users"

  def route(%Plug.Conn{params: %{"command" => "Login", "username" => username} = params}) do
    # TODO: implement macro command
    # command "Login", username: username, aggregate_id: "user/#{username}"
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

  def handle(%{command: "Login"} = command, aggregate) do
    # TODO: implement macro event
    # event "LoggedIn", command, aggregate, username: username, timer_id: aggregate["timer_id"]
    {:ok, %{event: "LoggedIn",
            username: command.username,
            command_id: command.id,
            aggregate_id: aggregate["id"],
            timer_id: aggregate["timer_id"],
            id: Veggy.UUID.new}}
  end

  def process(_event, s), do: s
end

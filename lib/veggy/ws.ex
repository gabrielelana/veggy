defmodule Veggy.WS do
  @behaviour :cowboy_websocket_handler
  @timeout 60000

  def init(_, _req, _opts) do
    {:upgrade, :protocol, :cowboy_websocket}
  end

  def websocket_init(_type, req, _opts) do
    {:ok, req, %{}, @timeout}
  end

  def websocket_handle({:text, "ping"}, req, state) do
    {:reply, {:text, "pong"}, req, state}
  end
  def websocket_handle({:text, "login:" <> username}, req, state) do
    # TODO: Veggy.Aggregate.User.user_id(username)
    Veggy.EventStore.subscribe(self, &related_to_user("user/#{username}", &1))
    {:reply, {:text, "ok"}, req, state}
  end
  def websocket_handle({_kind, _message}, req, state) do
    {:ok, req, state}
  end

  def websocket_info({:event, event}, req, state) do
    {:reply, {:text, Poison.encode!(event)}, req, state}
  end
  def websocket_info(_message, req, state) do
    {:ok, req, state}
  end

  def websocket_terminate(_reason, _req, _state) do
    :ok
  end

  defp related_to_user(user_id, %{event: _, user_id: user_id}), do: true
  defp related_to_user(_, _), do: false
end

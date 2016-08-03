defmodule Veggy.WS do
  @behaviour :cowboy_websocket_handler
  @timeout 60000

  def init(_, _req, _opts) do
    {:upgrade, :protocol, :cowboy_websocket}
  end

  def websocket_init(_type, req, _opts) do
    :timer.send_interval(5000, self, {:timer, "Hello"})
    {:ok, req, %{}, @timeout}
  end

  def websocket_handle({:text, message}, req, state) do
    {:reply, {:text, "He said `#{message}`"}, req, state}
  end
  def websocket_handle({_kind, _message}, req, state) do
    {:ok, req, state}
  end

  def websocket_info({:timer, message}, req, state) do
    {:reply, {:text, "Timer said `#{message}`"}, req, state}
  end
  def websocket_info(_message, req, state) do
    {:ok, req, state}
  end

  def websocket_terminate(_reason, _req, _state) do
    :ok
  end
end

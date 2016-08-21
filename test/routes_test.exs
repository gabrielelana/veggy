defmodule Veggy.RoutesTest do
  use ExUnit.Case, async: true
  use Plug.Test

  import Plug.Conn

  test "StartPomodoro" do
    timer_id = Veggy.UUID.new
    Veggy.EventStore.subscribe(self, &match?(%{event: "PomodoroEnded"}, &1))

    conn = conn(:post, "/timers/#{timer_id}", Poison.encode! %{command: "StartPomodoro", duration: 10})
    |> put_req_header("content-type", "application/json")
    |> call

    assert_command_received(conn)
    assert_receive {:event, %{event: "PomodoroEnded"}}
  end

  test "Login" do
    Veggy.EventStore.subscribe(self, &match?(%{event: "LoggedIn"}, &1))

    conn = conn(:post, "/commands", Poison.encode! %{command: "Login", username: "gabriele"})
    |> put_req_header("content-type", "application/json")
    |> call

    command_id = assert_command_received(conn)
    command_id = %BSON.ObjectId{value: Base.decode16!(command_id, case: :lower)}
    assert_receive {:event, %{event: "LoggedIn", command_id: ^command_id, timer_id: _}}
  end

  defp assert_command_received(conn) do
    assert conn.status == 201
    assert {"content-type", "application/json"} in conn.resp_headers

    command = Poison.decode!(conn.resp_body)
    expected_location = "#{conn.scheme}://#{conn.host}:#{conn.port}/commands/#{command["id"]}"
    assert {"location", expected_location} in conn.resp_headers

    command["id"]
  end

  defp call(conn), do: Veggy.HTTP.call(conn, [])
end

defmodule Veggy.RoutesTest do
  use ExUnit.Case, async: true
  use Plug.Test

  import Plug.Conn

  test "StartPomodoro" do
    Veggy.EventStore.subscribe(self, &match?(%{event: "PomodoroEnded"}, &1))

    timer_id = Veggy.UUID.new
    command = %{command: "StartPomodoro", timer_id: timer_id, duration: 10}
    conn = conn(:post, "/commands", Poison.encode! command)
    |> put_req_header("content-type", "application/json")
    |> call

    assert_command_received(conn)
    assert_receive {:event, %{event: "PomodoroEnded", aggregate_id: ^timer_id}}
  end

  test "Login" do
    Veggy.EventStore.subscribe(self, &match?(%{event: "LoggedIn"}, &1))

    conn = conn(:post, "/commands", Poison.encode! %{command: "Login", username: "gabriele"})
    |> put_req_header("content-type", "application/json")
    |> call

    command_id = assert_command_received(conn)
    command_id = %BSON.ObjectId{value: Base.decode16!(command_id, case: :lower)}
    assert_receive {:event, %{event: "LoggedIn", command_id: ^command_id, timer_id: _}}, 1000
  end

  test "not a valid command" do
    conn = conn(:post, "/commands", Poison.encode! %{command: "WhatCommandIsThis"})
    |> put_req_header("content-type", "application/json")
    |> call

    assert conn.status == 400
    assert {"content-type", "application/json"} in conn.resp_headers

    response = Poison.decode!(conn.resp_body)
    assert %{"error" => "unknown_command"} == response
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

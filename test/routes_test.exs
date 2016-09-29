defmodule Veggy.RoutesTest do
  use ExUnit.Case, async: true
  use Plug.Test

  import Plug.Conn

  test "command StartPomodoro" do
    Veggy.EventStore.subscribe(self, &match?(%{"event" => "PomodoroCompleted"}, &1))

    timer_id = Veggy.UUID.new
    command = %{"command" => "StartPomodoro", "timer_id" => timer_id, "duration" => 10}
    conn = conn(:post, "/commands", Poison.encode! command)
    |> put_req_header("content-type", "application/json")
    |> call

    assert_command_received(conn)
    assert_receive {:event, %{"event" => "PomodoroCompleted", "aggregate_id" => ^timer_id}}
  end

  test "command StartPomodoro with description" do
    Veggy.EventStore.subscribe(self, &match?(%{"event" => "PomodoroStarted"}, &1))

    timer_id = Veggy.UUID.new
    description = "Something to do"
    command = %{"command" => "StartPomodoro", "timer_id" => timer_id, "duration" => 10, "description" => description}
    conn = conn(:post, "/commands", Poison.encode! command)
    |> put_req_header("content-type", "application/json")
    |> call

    assert_command_received(conn)
    assert_receive {:event, %{"event" => "PomodoroStarted", "aggregate_id" => ^timer_id, "description" => ^description}}
  end

  test "command SquashPomodoro" do
    Veggy.EventStore.subscribe(self, &match?(%{"event" => "PomodoroCompleted"}, &1))
    Veggy.EventStore.subscribe(self, &match?(%{"event" => "PomodoroSquashed"}, &1))

    timer_id = Veggy.UUID.new
    command = %{"command" => "StartPomodoro", "timer_id" => timer_id, "duration" => 1000}
    conn = conn(:post, "/commands", Poison.encode! command)
    |> put_req_header("content-type", "application/json")
    |> call
    assert_command_received(conn)

    command = %{"command" => "SquashPomodoro", "timer_id" => timer_id}
    conn = conn(:post, "/commands", Poison.encode! command)
    |> put_req_header("content-type", "application/json")
    |> call
    assert_command_received(conn)

    refute_receive {:event, %{"event" => "PomodoroCompleted", "aggregate_id" => ^timer_id}}
    assert_receive {:event, %{"event" => "PomodoroSquashed", "aggregate_id" => ^timer_id}}
  end

  test "command Login" do
    Veggy.EventStore.subscribe(self, &match?(%{"event" => "LoggedIn"}, &1))

    conn = conn(:post, "/commands", Poison.encode! %{"command" => "Login", "username" => "gabriele"})
    |> put_req_header("content-type", "application/json")
    |> call

    command_id = assert_command_received(conn)
    command_id = Veggy.MongoDB.ObjectId.from_string(command_id)
    assert_receive {:event, %{"event" => "LoggedIn", "command_id" => ^command_id, "timer_id" => _}}, 1000
  end

  test "invalid command" do
    conn = conn(:post, "/commands", Poison.encode! %{"command" => "WhatCommandIsThis"})
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
    expected_location = "#{conn.scheme}://#{conn.host}:#{conn.port}/projections/command-status?command_id=#{command["_id"]}"
    assert {"location", expected_location} in conn.resp_headers

    command["_id"]
  end

  defp call(conn), do: Veggy.HTTP.call(conn, [])
end

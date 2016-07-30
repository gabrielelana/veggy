defmodule Veggy.RoutesTest do
  use ExUnit.Case, async: true
  use Plug.Test

  import Plug.Conn

  test "POST /timer" do
    conn = conn(:post, "/timer", Poison.encode! %{command: "StartPomodoro", duration: 10})
    |> put_req_header("content-type", "application/json")
    |> call

    assert conn.status == 201
    assert {"content-type", "application/json"} in conn.resp_headers

    command = Poison.decode!(conn.resp_body)
    expected_location = "#{conn.scheme}://#{conn.host}:#{conn.port}/commands/#{command["id"]}"
    assert {"location", expected_location} in conn.resp_headers
  end

  defp call(conn), do: Veggy.HTTP.call(conn, [])
end

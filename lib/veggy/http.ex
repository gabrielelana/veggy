defimpl String.Chars, for: BSON.ObjectId do
  def to_string(%BSON.ObjectId{value: value}) do
    Base.encode16(value, case: :lower)
  end
end

defimpl Poison.Encoder, for: BSON.ObjectId do
  def encode(%BSON.ObjectId{} = oid, options) do
    Poison.Encoder.BitString.encode(String.Chars.to_string(oid), options)
  end
end

defmodule Veggy.HTTP do
  use Plug.Router
  require Logger

  plug Plug.Logger
  plug Plug.Parsers, parsers: [:json], pass: ["application/json"], json_decoder: Poison
  plug :match
  plug :dispatch

  get "/ping" do
    conn
    |> put_resp_header("content-type", "plain/text")
    |> send_resp(200, "pong")
  end

  post "/counters/:name" do
    %{"counter" => counter} = count_up(name)
    conn
    |> put_resp_header("content-type", "plain/text")
    |> send_resp(200, "#{counter}")
  end

  post "/timer" do
    command = command_from(conn.params)
    Veggy.Registry.dispatch(command)
    Process.sleep(1000)

    conn
    |> put_resp_header("content-type", "application/json")
    |> put_resp_header("location", url_for(conn, "/commands/#{command.id}"))
    |> send_resp(201, Poison.encode!(command))
  end

  match _ do
    conn
    |> put_resp_header("content-type", "plain/text")
    |> send_resp(404, "oops")
  end

  defp count_up(counter_name) do
    collection = "counters"
    query = %{name: counter_name}
    Mongo.update_one(Veggy.MongoDB, collection, query, %{"$inc": %{counter: 1}}, upsert: true)
    Mongo.find(Veggy.MongoDB, collection, query) |> Enum.to_list |> List.first
  end

  defp command_from(%{"command" => "StartPomodoro"} = params) do
    %{command: "StartPomodoro",
      aggregate_id: "timer/XXX",
      aggregate_kind: "Timer",
      duration: Map.get(params, "duration", 25*60*1000),
      id: Mongo.IdServer.new}
  end

  defp url_for(conn, path) do
    Atom.to_string(conn.scheme) <> "://" <>
      conn.host <> ":" <> Integer.to_string(conn.port) <>
      path
  end
end

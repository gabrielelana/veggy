defmodule Veggy.HTTP do
  use Plug.Router
  require Logger

  plug Plug.Logger
  plug Plug.Static, at: "/", from: "priv/static"
  plug Plug.Parsers, parsers: [:json], pass: ["application/json"], json_decoder: Poison
  plug CORSPlug
  plug :match
  plug :dispatch

  get "/ping" do
    conn
    |> put_resp_header("content-type", "plain/text")
    |> send_resp(200, "pong")
  end

  post "/commands" do
    case Veggy.Aggregates.dispatch(conn) do
      {:ok, command} ->
        conn
        |> put_resp_header("content-type", "application/json")
        |> put_resp_header("location", url_for(conn, "/commands/#{command.id}"))
        |> send_resp(201, Poison.encode!(command))
      {:error, reason} ->
        conn
        |> put_resp_header("content-type", "application/json")
        |> send_resp(400, Poison.encode!(%{error: reason}))
    end
  end

  get "/commands/:command_id" do
    command_id = %BSON.ObjectId{value: Base.decode16!(command_id, case: :lower)}
    case Veggy.Projection.Commands.status_of(command_id) do
      {:ok, command} ->
        conn
        |> put_resp_header("content-type", "application/json")
        |> send_resp(200, Poison.encode!(command))
      {:error, :not_found} ->
        conn
        |> send_resp(404, "")
    end
  end

  get "/timers/:timer_id/pomodori/latest" do
    case Veggy.Projection.Pomodori.latest_pomodoro_for_timer(timer_id) do
      {:ok, pomodoro} ->
        response = %{started_at: to_datetime(pomodoro["started_at"]),
                     current_time: DateTime.utc_now,
                     ticking: pomodoro["ticking"]}
        conn
        |> put_resp_header("content-type", "application/json")
        |> put_resp_header("location", url_for(conn, "/pomodori/#{pomodoro["pomodoro_id"]}"))
        |> send_resp(200, Poison.encode!(response))
      {:error, :not_found} ->
        conn
        |> send_resp(404, "")
    end
  end

  get "/timers/pomodori/latest" do
    {:ok, latest_pomodori} = Veggy.Projection.LatestPomodori.all
    conn
    |> put_resp_header("content-type", "application/json")
    |> send_resp(200, Poison.encode!(latest_pomodori))
  end

  match _ do
    conn
    |> put_resp_header("content-type", "plain/text")
    |> send_resp(404, "oops")
  end

  defp to_datetime(%BSON.DateTime{} = bdt) do
    {date, {h, m, s, _}} = BSON.DateTime.to_datetime(bdt)
    ts = :calendar.datetime_to_gregorian_seconds({date, {h, m, s}}) - 62167219200
    {:ok, dt} = DateTime.from_unix(ts)
    dt
  end

  defp url_for(conn, path) do
    Atom.to_string(conn.scheme) <> "://" <>
      conn.host <> ":" <> Integer.to_string(conn.port) <>
      path
  end
end

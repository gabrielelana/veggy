defmodule Veggy.HTTP do
  use Plug.Router

  plug Plug.Logger
  plug :match
  plug :dispatch

  get "/ping" do
    conn
    |> put_resp_header("Content-Type", "plain/text")
    |> send_resp(200, "pong")
  end

  match _ do
    conn
    |> send_resp(400, "oops")
  end
end

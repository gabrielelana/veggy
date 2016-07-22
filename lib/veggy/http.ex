defmodule Veggy.HTTP do
  import Plug.Conn

  def init(options), do: options

  def call(conn, _) do
    conn
    |> put_resp_header("Content-Type", "plain/text")
    |> send_resp(200, "Hello World")
  end
end

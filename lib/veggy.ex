defmodule Veggy do
  use Application

  defmodule MongoDB do
    use Mongo.Pool, name: __MODULE__, adapter: Mongo.Pool.Poolboy

    def child_spec do
      Supervisor.Spec.worker(__MODULE__, [[
        hostname: System.get_env("MONGODB_HOST") || "localhost",
        database: System.get_env("MONGODB_DBNAME") || "veggy",
        username: System.get_env("MONGODB_USERNAME"),
        password: System.get_env("MONGODB_PASSWORD"),
      ]])
    end
  end







  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    # Define workers and child supervisors to be supervised
    children = [
      MongoDB.child_spec,
      worker(Veggy.EventStore, []),
      worker(Veggy.Countdown, []),
      worker(Veggy.Registry, []),
      worker(Veggy.Projection, [Veggy.Projection.Pomodori]),
      Plug.Adapters.Cowboy.child_spec(:http, Veggy.HTTP, [],
        [port: 4000, dispatch: dispatch]),
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Veggy.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp dispatch do
    websocket = {"/ws", Veggy.WS, []}
    otherwise = {:_, Plug.Adapters.Cowboy.Handler, {Veggy.HTTP, []}}
    [{:_, [websocket, otherwise]}]
  end
end

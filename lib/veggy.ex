defmodule Veggy do
  use Application

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    # Define workers and child supervisors to be supervised
    children = [
      Veggy.MongoDB.child_spec,
      worker(Veggy.EventStore, []),
      worker(Veggy.Countdown, []),
      worker(Veggy.Aggregates, [
            [Veggy.Aggregate.Timer,
             Veggy.Aggregate.User]]),
      worker(Veggy.Projections, [[Veggy.Projection.Pomodori]]),
            # [Veggy.Projection.Commands,
            #  Veggy.Projection.Pomodori,
            #  Veggy.Projection.LatestPomodori]]),
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
